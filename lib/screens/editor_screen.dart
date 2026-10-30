import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../data/templates.dart';
import '../services/platform_service.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/formatting.dart';
import '../widgets/mood_meter.dart';
import '../widgets/template_sheet.dart';
import '../widgets/entry_link_sheet.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    super.key,
    this.entryId,
    this.initialDate,
    this.journalId,
  });

  /// null = new entry.
  final int? entryId;
  final DateTime? initialDate;
  final int? journalId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  QuillController? _quill;
  final _titleController = TextEditingController();
  final _editorFocus = FocusNode();

  int? _entryId;
  int? _journalId;
  late DateTime _entryDate;
  int? _mood;
  bool _isDraft = true;
  int _savedWritingSeconds = 0;
  List<Tag> _tags = [];

  /// Fires on any edit; debounced into the auto-save.
  final _dirty = PublishSubject<void>();
  StreamSubscription? _autoSaveSub;
  StreamSubscription? _docSub;
  final _stopwatch = Stopwatch();
  final _wordCount = ValueNotifier<int>(0);
  DateTime? _lastSavedAt;
  Timer? _ticker;
  bool _focusMode = false;
  bool _saveFailed = false;
  int _revision = 0;
  int _savedRevision = -1;
  bool _hasEdited = false;
  StreamSubscription? _dirtySub;
  bool _closing = false;
  bool _recording = false;
  bool _hasAttachments = false;
  late final AppDatabase _database;
  String? _location;
  String? _inlineTag;
  bool _shortcutBusy = false;
  DateTime _createdAt = DateTime.now();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_closing) _stopwatch.start();
    } else {
      _stopwatch.stop();
      if (_recording && !_closing) _voice();
      if (_quill != null && !_isEmpty && !_closing) {
        _persist(draft: _isDraft || _hasEdited).catchError((Object e) {});
      }
    }
  }

  void _documentShortcuts() {
    if (_shortcutBusy || _quill == null) return;
    final q = _quill!;
    final offset = q.selection.baseOffset;
    final plain = q.document.toPlainText();
    if (offset < 0 || offset > plain.length) return;
    final start = plain.lastIndexOf('\n', offset > 0 ? offset - 1 : 0) + 1;
    final prefix = plain.substring(start.clamp(0, offset), offset);
    final markers = <String, Attribute>{
      '# ': Attribute.h1,
      '## ': Attribute.h2,
      '- ': Attribute.ul,
      '1. ': Attribute.ol,
      '> ': Attribute.blockQuote,
    };
    final attribute = markers[prefix];
    if (attribute != null) {
      _shortcutBusy = true;
      q.replaceText(
        start,
        prefix.length,
        '',
        TextSelection.collapsed(offset: start),
      );
      q.formatSelection(attribute);
      _shortcutBusy = false;
    }
    final tag = RegExp(r'(?:^|\s)#([\w-]*)$').firstMatch(prefix);
    if (mounted && _inlineTag != tag?.group(1)) {
      setState(() => _inlineTag = tag?.group(1));
    }
    if (prefix.endsWith('[[') && !_shortcutBusy) {
      _shortcutBusy = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _linkEntry().whenComplete(() => _shortcutBusy = false),
      );
    }
  }

  Future<void> _linkEntry() async {
    final chosen = await showEntryLinkSheet(context, excludeId: _entryId);
    if (chosen == null || _quill == null || !mounted) return;
    final q = _quill!;
    final offset = q.selection.baseOffset;
    final plain = q.document.toPlainText();
    final remove = offset >= 2 && plain.substring(offset - 2, offset) == '[['
        ? 2
        : 0;
    final label = chosen.title.isEmpty
        ? DateFormat.yMMMd().format(chosen.entryDate)
        : chosen.title;
    q.replaceText(
      offset - remove,
      remove,
      label,
      TextSelection.collapsed(offset: offset - remove + label.length),
    );
    q.formatText(
      offset - remove,
      label.length,
      LinkAttribute('journal://entry/${chosen.stableId}'),
    );
  }

  Future<void> _saveTemplate() async {
    final db = ref.read(databaseProvider);
    final name = _titleController.text.trim().isEmpty
        ? 'My template'
        : _titleController.text.trim();
    final templates = jsonDecode(await db.setting('templates') ?? '[]') as List;
    templates.removeWhere((t) => t['name'] == name);
    templates.add({
      'name': name,
      'delta': jsonEncode(_quill!.document.toDelta().toJson()),
    });
    await db.setSetting('templates', jsonEncode(templates));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved as a writing template')),
      );
    }
  }

  Future<void> _voice() async {
    try {
      if (_recording) {
        final path = await PlatformService.stopRecording();
        setState(() => _recording = false);
        if (path != null) {
          final name = await ref
              .read(attachmentServiceProvider)
              .storeFile(path);
          await _persist(draft: true);
          await ref.read(databaseProvider).addAttachment(_entryId!, name);
          if (mounted) setState(() => _hasAttachments = true);
        }
      } else {
        final path = await PlatformService.startRecording();
        if (path != null && mounted) setState(() => _recording = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Voice note unavailable: $e')));
      }
    }
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'focus':
        setState(() => _focusMode = !_focusMode);
      case 'template':
        await _pickTemplate();
      case 'saveTemplate':
        await _saveTemplate();
      case 'photo':
        await _attachImage();
      case 'voice':
        await _voice();
      case 'link':
        await _linkEntry();
      case 'location':
        try {
          final location = await PlatformService.location();
          if (mounted && location != null) {
            setState(() => _location = location);
            _dirty.add(null);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Location unavailable: $e')));
          }
        }
      case 'clearLocation':
        setState(() => _location = null);
        _dirty.add(null);
      case 'delete':
        _closing = true;
        await _autoSaveSub?.cancel();
        await _persistQueue;
        if (_entryId != null) {
          await ref.read(databaseProvider).deleteEntry(_entryId!);
        }
        if (mounted) {
          Navigator.of(context).pop();
        }
    }
  }

  @override
  void initState() {
    super.initState();
    _entryDate = widget.initialDate ?? DateTime.now();
    _journalId = widget.journalId;
    _entryId = widget.entryId;
    _database = ref.read(databaseProvider);
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _stopwatch.isRunning) setState(() {});
    });
    _stopwatch.start();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    Document doc;
    if (_entryId != null) {
      final entry = await db.getEntry(_entryId!);
      if (entry != null) {
        _createdAt = entry.createdAt;
        _location = entry.location;
        _titleController.text = entry.title;
        _journalId = entry.journalId;
        _entryDate = entry.entryDate;
        _mood = entry.mood;
        _isDraft = entry.isDraft;
        _savedWritingSeconds = entry.writingSeconds;
        _lastSavedAt = entry.updatedAt;
        _tags = await db.tagsForEntry(entry.id);
        _hasAttachments = (await db.attachmentsForEntry(entry.id)).isNotEmpty;
        doc = Document.fromJson(jsonDecode(entry.contentJson) as List);
      } else {
        doc = Document();
      }
    } else {
      doc = Document();
    }
    _journalId ??= (await db.select(db.journals).get()).firstOrNull?.id;

    if (!mounted) return;
    setState(() {
      _quill = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    });
    _quill!.addListener(_documentShortcuts);
    _recountWords();

    // Auto-save draft: debounce edits (2s quiet period) before hitting the DB.
    _bindDocument();
    _titleController.addListener(() => _dirty.add(null));
    _autoSaveSub = _dirty.debounceTime(const Duration(seconds: 2)).listen((_) {
      if (!_closing && !_isEmpty) {
        _persist(draft: true).catchError((Object e) {});
      }
    });
    _savedRevision = _revision;
    _dirtySub = _dirty.listen((_) {
      _hasEdited = true;
      if (mounted) setState(() => _revision++);
    });

    if (widget.entryId == null) {
      final saved = await db.setting('default_template');
      if (saved != null && mounted && _isEmpty) {
        _quill!.document = Document.fromJson(jsonDecode(saved) as List);
        _bindDocument();
        _recountWords();
      }
    }
  }

  /// Subscribes to the *current* document.
  ///
  /// `QuillController.document = doc` swaps in a new [Document], and each one
  /// owns its own `changes` stream — a subscription taken before the swap goes
  /// silent, which is how loading a template used to freeze the word count.
  /// Every place that replaces the document calls this again.
  void _bindDocument() {
    _docSub?.cancel();
    _docSub = _quill!.document.changes.listen((_) {
      _recountWords();
      _dirty.add(null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _documentShortcuts();
      });
    });
  }

  void _recountWords() {
    _wordCount.value = countWords(_quill!.document.toPlainText());
  }

  bool get _isEmpty =>
      _titleController.text.trim().isEmpty &&
      _quill!.document.toPlainText().trim().isEmpty &&
      !_hasAttachments;

  /// Serializes writes: the debounced auto-save can fire while an attachment
  /// or tag edit is still persisting, and two overlapping runs would both see
  /// a null `_entryId` and insert the entry twice.
  Future<void> _persistQueue = Future.value();

  Future<void> _persist({required bool draft}) {
    if (_quill == null || _journalId == null) return Future.value();
    // Capture the document before predictive back removes this route. The
    // queued write owns its data and never reads a disposed controller or ref.
    final plain = _quill!.document.toPlainText().trim();
    final revision = _revision;
    final value = EntriesCompanion(
      journalId: Value(_journalId!),
      title: Value(_titleController.text.trim()),
      contentJson: Value(jsonEncode(_quill!.document.toDelta().toJson())),
      plainText: Value(plain),
      entryDate: Value(_entryDate),
      updatedAt: Value(DateTime.now()),
      wordCount: Value(countWords(plain)),
      writingSeconds: Value(
        _savedWritingSeconds + _stopwatch.elapsed.inSeconds,
      ),
      mood: Value(_mood),
      location: Value(_location),
      isDraft: Value(draft),
    );
    final next = _persistQueue
        .then((_) async {
          if (_entryId == null) {
            _entryId = await _database.insertEntry(value);
          } else {
            await _database.updateEntry(_entryId!, value);
          }
          _isDraft = draft;
          _saveFailed = false;
          _savedRevision = revision;
          if (mounted) setState(() => _lastSavedAt = DateTime.now());
        })
        .catchError((Object e) {
          if (mounted) setState(() => _saveFailed = true);
          throw e;
        });
    _persistQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _saveAndClose() async {
    if (_closing) return;
    if (_recording) await _voice();
    _closing = true;
    try {
      if (_isEmpty) {
        await _discardIfEmpty();
      } else {
        await _persist(draft: false);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _closing = false;
      if (mounted) setState(() => _saveFailed = true);
    }
  }

  Future<void> _discardIfEmpty() async {
    final empty = _isEmpty;
    await _persistQueue;
    if (_entryId != null && empty) {
      await _database.deleteEntry(_entryId!);
      _entryId = null;
    }
  }

  Future<void> _pickTemplate() async {
    final db = ref.read(databaseProvider);
    final custom = jsonDecode(await db.setting('templates') ?? '[]') as List;
    if (!mounted) return;
    final template = await showTemplateSheet(
      context,
      custom: [
        for (final t in custom)
          WritingTemplate(
            name: t['name'] as String,
            description: 'Your writing template',
            emoji: '??',
            deltaJson: t['delta'] as String,
          ),
      ],
    );
    if (template == null || _quill == null) return;
    await db.setSetting('default_template', template.deltaJson);
    final doc = Document.fromJson(jsonDecode(template.deltaJson) as List);
    _quill!.document = doc;
    _bindDocument();
    _recountWords();
    _dirty.add(null);
    _editorFocus.requestFocus();
  }

  Future<void> _attachImage() async {
    final source = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('From gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final name = await ref
        .read(attachmentServiceProvider)
        .pickImage(fromCamera: source);
    if (name == null) return;
    // Attachments need a row to point at — make sure the draft exists.
    if (_entryId == null) await _persist(draft: _isDraft);
    if (_entryId != null) {
      await ref.read(databaseProvider).addAttachment(_entryId!, name);
      if (mounted) setState(() => _hasAttachments = true);
    }
  }

  Future<void> _editTags() async {
    final db = ref.read(databaseProvider);
    final all = await db.select(db.tags).get();
    if (!mounted) return;
    final result = await showDialog<List<Tag>>(
      context: context,
      builder: (context) => _TagPickerDialog(allTags: all, selected: _tags),
    );
    if (result == null) return;
    setState(() => _tags = result);
    if (_entryId == null) await _persist(draft: _isDraft);
    if (_entryId != null) {
      await db.setEntryTags(_entryId!, result.map((t) => t.id).toList());
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(
      () => _entryDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _entryDate.hour,
        _entryDate.minute,
      ),
    );
    _dirty.add(null);
  }

  @override
  void dispose() {
    _autoSaveSub?.cancel();
    _docSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    if (_recording) PlatformService.stopRecording();
    _dirty.close();
    _dirtySub?.cancel();
    _stopwatch.stop();
    _titleController.dispose();
    _editorFocus.dispose();
    _wordCount.dispose();
    _quill?.removeListener(_documentShortcuts);
    _quill?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quill = _quill;
    if (quill == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final journals = ref.watch(journalsProvider).value ?? [];
    final theme = Theme.of(context);
    final t = context.tokens;

    final compact =
        MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom <
            520 ||
        _focusMode;
    return PopScope(
      canPop:
          !_recording &&
          !_saveFailed &&
          (_isEmpty || _savedRevision == _revision),
      onPopInvokedWithResult: (didPop, _) async {
        if (_closing) return;
        if (!didPop) {
          await _saveAndClose();
          return;
        }
        _closing = true;
        final finishing = _isEmpty ? _discardIfEmpty() : _persist(draft: false);
        await _autoSaveSub?.cancel();
        await finishing;
      },
      child: Scaffold(
        backgroundColor: t.page,
        appBar: _focusMode
            ? null
            : AppBar(
                backgroundColor: t.page,
                title: journals.isEmpty
                    ? null
                    : _JournalPicker(
                        journals: journals,
                        journalId: _journalId,
                        onChanged: (v) {
                          setState(() => _journalId = v);
                          _dirty.add(null);
                        },
                      ),
                titleSpacing: 4,
                actions: [
                  PopupMenuButton<String>(
                    tooltip: 'Entry actions',
                    onSelected: _menu,
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'focus',
                        child: Text('Focus mode'),
                      ),
                      const PopupMenuItem(
                        value: 'template',
                        child: Text('Start from a template'),
                      ),
                      const PopupMenuItem(
                        value: 'saveTemplate',
                        child: Text('Save as template'),
                      ),
                      const PopupMenuItem(
                        value: 'photo',
                        child: Text('Add a photo'),
                      ),
                      PopupMenuItem(
                        value: 'voice',
                        child: Text(
                          _recording ? 'Stop voice note' : 'Record voice note',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'link',
                        child: Text('Link another entry'),
                      ),
                      const PopupMenuItem(
                        value: 'location',
                        child: Text('Add current location'),
                      ),
                      if (_location != null)
                        const PopupMenuItem(
                          value: 'clearLocation',
                          child: Text('Remove location'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Move to recently deleted'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _saveAndClose,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Done'),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
        body: SafeArea(
          top: _focusMode,
          child: Column(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The date reads as a letterhead on the page, and tapping it
                    // is how an old memory gets filed under the day it happened.
                    if (!compact)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
                        child: TextButton.icon(
                          onPressed: _pickDate,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            foregroundColor: t.inkDim,
                          ),
                          icon: const Icon(Icons.event_outlined, size: 16),
                          label: Text(
                            DateFormat(
                              'd MMMM yyyy',
                            ).format(_entryDate).toUpperCase(),
                            style: theme.textTheme.utility.copyWith(
                              color: t.inkDim,
                            ),
                          ),
                        ),
                      ),
                    if (!compact &&
                        dayOrdinal(DateTime.now()) - dayOrdinal(_entryDate) > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Filed under ${DateFormat.MMMd().format(_entryDate)} \u00b7 written ${dayOrdinal(_createdAt) == dayOrdinal(DateTime.now()) ? "today" : DateFormat.yMMMd().format(_createdAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (!compact && _location != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          _location!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (!compact && widget.entryId != null && _isDraft)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Recovered writing \u00b7 your last autosave is here.',
                        ),
                      ),
                    if (!compact)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                        child: TextField(
                          controller: _titleController,
                          style: theme.textTheme.displayMedium,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Title',
                            hintStyle: theme.textTheme.displayMedium!.copyWith(
                              color: t.inkFaint,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 6,
                            ),
                          ),
                        ),
                      ),
                    if (!compact) _TagRow(tags: _tags, onEdit: _editTags),
                    if (!compact && _entryId != null)
                      _AttachmentStrip(
                        entryId: _entryId!,
                        onChanged: (hasAttachments) {
                          if (mounted) {
                            setState(() => _hasAttachments = hasAttachments);
                          }
                        },
                      ),
                    if (_inlineTag != null && !compact)
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final tag
                                in (ref.watch(tagsProvider).value ?? <Tag>[])
                                    .where(
                                      (t) => t.name.startsWith(_inlineTag!),
                                    ))
                              TextButton(
                                onPressed: () async {
                                  final q = _quill!;
                                  final offset = q.selection.baseOffset;
                                  final start = offset - _inlineTag!.length;
                                  q.replaceText(
                                    start,
                                    _inlineTag!.length,
                                    '${tag.name} ',
                                    TextSelection.collapsed(
                                      offset: start + tag.name.length + 1,
                                    ),
                                  );
                                  if (!_tags.any((t) => t.id == tag.id)) {
                                    _tags.add(tag);
                                  }
                                  await _persist(draft: true);
                                  await ref
                                      .read(databaseProvider)
                                      .setEntryTags(
                                        _entryId!,
                                        _tags.map((t) => t.id).toList(),
                                      );
                                },
                                child: Text('#${tag.name}'),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      // Quill derives every style from the ambient DefaultTextStyle,
                      // so the reading face is set once here rather than per block.
                      child: DefaultTextStyle(
                        style: theme.textTheme.bodyLarge!,
                        child: QuillEditor.basic(
                          controller: quill,
                          focusNode: _editorFocus,
                          config: QuillEditorConfig(
                            onLaunchUrl: (url) async {
                              final uri = Uri.tryParse(url);
                              if (uri == null) return;
                              if (uri.scheme != 'journal' ||
                                  uri.host != 'entry') {
                                if ([
                                  'http',
                                  'https',
                                  'mailto',
                                ].contains(uri.scheme)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                                return;
                              }
                              if (uri.pathSegments.isEmpty) return;
                              final target = await ref
                                  .read(databaseProvider)
                                  .getEntryByStableId(uri.pathSegments.last);
                              if (target != null && context.mounted) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EditorScreen(entryId: target.id),
                                  ),
                                );
                              }
                            },
                            placeholder: 'Write about today',
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            customStyles: DefaultStyles(
                              paragraph: DefaultTextBlockStyle(
                                theme.textTheme.bodyLarge!,
                                const HorizontalSpacing(0, 0),
                                const VerticalSpacing(0, 8),
                                VerticalSpacing.zero,
                                null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact)
                _MoodStrip(
                  mood: _mood,
                  onChanged: (m) {
                    setState(() => _mood = m);
                    _dirty.add(null);
                  },
                ),
              if (!compact)
                Container(
                  decoration: BoxDecoration(
                    color: t.ground,
                    border: Border(top: BorderSide(color: t.hairline)),
                  ),
                  child: QuillSimpleToolbar(
                    controller: quill,
                    config: QuillSimpleToolbarConfig(
                      multiRowsDisplay: false,
                      showFontFamily: false,
                      showFontSize: false,
                      showSubscript: false,
                      showSuperscript: false,
                      showSearchButton: false,
                      showAlignmentButtons: false,
                      showIndent: false,
                      showDividers: false,
                      showBackgroundColorButton: false,
                      toolbarIconAlignment: WrapAlignment.start,
                      buttonOptions: QuillSimpleToolbarButtonOptions(
                        base: QuillToolbarBaseButtonOptions(
                          iconSize: 17,
                          iconTheme: QuillIconTheme(
                            iconButtonUnselectedData: IconButtonData(
                              color: t.inkDim,
                              highlightColor: Colors.transparent,
                            ),
                            iconButtonSelectedData: IconButtonData(
                              color: t.ink,
                              style: IconButton.styleFrom(
                                backgroundColor: t.pageEdge,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: Radii.chip,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              InkWell(
                onTap: _focusMode
                    ? () => setState(() => _focusMode = false)
                    : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  color: t.ground,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        formatWords(_wordCount.value),
                        style: theme.textTheme.labelSmall,
                      ),
                      if (!_focusMode)
                        Text(
                          '${formatTotalTime(_stopwatch.elapsed.inSeconds)} this session \u00b7 ${formatTotalTime(_savedWritingSeconds + _stopwatch.elapsed.inSeconds)} total',
                          style: theme.textTheme.labelSmall,
                        ),
                      if (_saveFailed)
                        TextButton(
                          onPressed: () =>
                              _persist(draft: true).catchError((Object e) {}),
                          child: Text(
                            'Save failed · retry',
                            style: TextStyle(color: t.danger),
                          ),
                        )
                      else if (!_focusMode)
                        Text(
                          _lastSavedAt == null
                              ? 'Not saved yet'
                              : _savedRevision != _revision
                              ? 'Waiting to save'
                              : 'Saved on device',
                          style: theme.textTheme.labelSmall,
                        ),
                      if (_focusMode) const Text('Tap to show controls'),
                      if (_recording)
                        TextButton(
                          onPressed: _voice,
                          child: const Text('Stop recording'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which notebook this entry belongs to.
class _JournalPicker extends StatelessWidget {
  const _JournalPicker({
    required this.journals,
    required this.journalId,
    required this.onChanged,
  });

  final List<Journal> journals;
  final int? journalId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final current = journals.where((j) => j.id == journalId).firstOrNull;
    return PopupMenuButton<int>(
      tooltip: 'Change journal',
      color: t.page,
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final j in journals)
          PopupMenuItem(
            value: j.id,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Color(j.color),
                    borderRadius: const BorderRadius.all(Radius.circular(1.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${j.emoji} ${j.name}', style: text.titleSmall),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (current != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Color(current.color),
                  borderRadius: const BorderRadius.all(Radius.circular(1.5)),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  current.name.toUpperCase(),
                  style: text.utility.copyWith(color: t.inkDim),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            Icon(Icons.expand_more, size: 16, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// How the day felt, asked once, at the foot of the page.
class _MoodStrip extends StatelessWidget {
  const _MoodStrip({required this.mood, required this.onChanged});

  final int? mood;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.page,
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: MoodPicker(mood: mood, onChanged: onChanged),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags, required this.onEdit});
  final List<Tag> tags;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final tag in tags)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  '#${tag.name}',
                  style: text.meta.copyWith(color: t.inkDim),
                ),
              ),
            ),
          Center(
            child: TextButton.icon(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: t.inkDim,
              ),
              icon: Icon(Icons.sell_outlined, size: 15, color: t.inkDim),
              label: Text(
                tags.isEmpty ? 'Add tags' : 'Edit tags',
                style: text.meta.copyWith(color: t.inkDim),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentStrip extends ConsumerWidget {
  const _AttachmentStrip({required this.entryId, required this.onChanged});
  final int entryId;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final service = ref.watch(attachmentServiceProvider);
    final items =
        ref.watch(attachmentsForEntryProvider(entryId)).value ?? <Attachment>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final a = items[i];
          return FutureBuilder<File>(
            future: service.fileFor(a.fileName),
            builder: (context, fileSnap) {
              final file = fileSnap.data;
              if (file == null) return const SizedBox.shrink();
              if (a.fileName.endsWith('.m4a')) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => PlatformService.play(file.path),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Voice note'),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _showFull(context, file, () async {
                    await db.removeAttachment(a.id);
                    onChanged(
                      (await db.attachmentsForEntry(entryId)).isNotEmpty,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Photo removed'),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () async {
                              await db.addAttachment(entryId, a.fileName);
                              onChanged(true);
                            },
                          ),
                        ),
                      );
                    }
                  }),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      file,
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showFull(
    BuildContext context,
    File file,
    Future<void> Function() onDelete,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Image.file(file, fit: BoxFit.contain),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                  onPressed: () async {
                    await onDelete();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPickerDialog extends ConsumerStatefulWidget {
  const _TagPickerDialog({required this.allTags, required this.selected});
  final List<Tag> allTags;
  final List<Tag> selected;

  @override
  ConsumerState<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends ConsumerState<_TagPickerDialog> {
  late List<Tag> _all = [...widget.allTags];
  late final Set<int> _selectedIds = widget.selected.map((t) => t.id).toSet();
  final _newTagController = TextEditingController();

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim().replaceAll('#', '');
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    final id = await db.ensureTag(name);
    _newTagController.clear();
    setState(() {
      if (!_all.any((t) => t.id == id)) {
        _all = [..._all, Tag(id: id, name: name)];
      }
      _selectedIds.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newTagController,
              decoration: InputDecoration(
                hintText: 'New tag…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _createTag,
                ),
              ),
              onSubmitted: (_) => _createTag(),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in _all)
                      FilterChip(
                        label: Text('#${t.name}'),
                        selected: _selectedIds.contains(t.id),
                        onSelected: (sel) => setState(
                          () => sel
                              ? _selectedIds.add(t.id)
                              : _selectedIds.remove(t.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _all.where((t) => _selectedIds.contains(t.id)).toList(),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
