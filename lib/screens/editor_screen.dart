import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';

import '../data/database.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/formatting.dart';
import '../widgets/mood_meter.dart';
import '../widgets/template_sheet.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, this.entryId, this.initialDate, this.journalId});

  /// null = new entry.
  final int? entryId;
  final DateTime? initialDate;
  final int? journalId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
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

  @override
  void initState() {
    super.initState();
    _entryDate = widget.initialDate ?? DateTime.now();
    _journalId = widget.journalId;
    _entryId = widget.entryId;
    _stopwatch.start();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    Document doc;
    if (_entryId != null) {
      final entry = await db.getEntry(_entryId!);
      if (entry != null) {
        _titleController.text = entry.title;
        _journalId = entry.journalId;
        _entryDate = entry.entryDate;
        _mood = entry.mood;
        _isDraft = entry.isDraft;
        _savedWritingSeconds = entry.writingSeconds;
        _tags = await db.tagsForEntry(entry.id);
        doc = Document.fromJson(jsonDecode(entry.contentJson) as List);
      } else {
        doc = Document();
      }
    } else {
      doc = Document();
    }
    _journalId ??= (await db.select(db.journals).get()).firstOrNull?.id;

    setState(() {
      _quill = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    });
    _recountWords();

    // Auto-save draft: debounce edits (2s quiet period) before hitting the DB.
    _bindDocument();
    _titleController.addListener(() => _dirty.add(null));
    _autoSaveSub = _dirty
        .debounceTime(const Duration(seconds: 2))
        .listen((_) => _persist(draft: _isDraft));

    // Offer templates when starting a brand-new entry.
    if (widget.entryId == null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickTemplate());
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
    });
  }

  void _recountWords() {
    _wordCount.value = countWords(_quill!.document.toPlainText());
  }

  bool get _isEmpty =>
      _titleController.text.trim().isEmpty &&
      _quill!.document.toPlainText().trim().isEmpty;

  /// Serializes writes: the debounced auto-save can fire while an attachment
  /// or tag edit is still persisting, and two overlapping runs would both see
  /// a null `_entryId` and insert the entry twice.
  Future<void> _persistQueue = Future.value();

  Future<void> _persist({required bool draft}) {
    final next = _persistQueue.then((_) => _write(draft: draft));
    _persistQueue = next.catchError((_) {});
    return next;
  }

  /// Writes the entry. Inserts on first call, updates afterwards.
  Future<void> _write({required bool draft}) async {
    if (_quill == null || _journalId == null) return;
    final db = ref.read(databaseProvider);

    final elapsed = _stopwatch.elapsed.inSeconds;
    _stopwatch.reset(); // keeps running; we accumulate into the stored total
    _savedWritingSeconds += elapsed;

    // Counted from the document being written, not from the notifier: the
    // stored count and the stored plain text then can never disagree.
    final plain = _quill!.document.toPlainText().trim();
    final words = countWords(plain);
    if (mounted) _wordCount.value = words;

    final companion = EntriesCompanion(
      journalId: Value(_journalId!),
      title: Value(_titleController.text.trim()),
      contentJson: Value(jsonEncode(_quill!.document.toDelta().toJson())),
      plainText: Value(plain),
      entryDate: Value(_entryDate),
      updatedAt: Value(DateTime.now()),
      wordCount: Value(words),
      writingSeconds: Value(_savedWritingSeconds),
      mood: Value(_mood),
      isDraft: Value(draft),
    );

    if (_entryId == null) {
      _entryId = await db.insertEntry(EntriesCompanion.insert(
        journalId: _journalId!,
        title: Value(_titleController.text.trim()),
        contentJson: jsonEncode(_quill!.document.toDelta().toJson()),
        plainText: Value(plain),
        entryDate: _entryDate,
        wordCount: Value(words),
        writingSeconds: Value(_savedWritingSeconds),
        mood: Value(_mood),
        isDraft: Value(draft),
      ));
    } else {
      await db.updateEntry(_entryId!, companion);
    }
    _isDraft = draft;
    if (mounted) setState(() => _lastSavedAt = DateTime.now());
  }

  Future<void> _saveAndClose() async {
    if (_isEmpty) {
      await _discardIfEmpty();
    } else {
      await _persist(draft: false);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _discardIfEmpty() async {
    if (_entryId != null && _isEmpty) {
      await ref.read(databaseProvider).deleteEntry(_entryId!);
      _entryId = null;
    }
  }

  Future<void> _pickTemplate() async {
    final template = await showTemplateSheet(context);
    if (template == null || _quill == null) return;
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
        ]),
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
    setState(() => _entryDate = DateTime(picked.year, picked.month, picked.day,
        _entryDate.hour, _entryDate.minute));
    _dirty.add(null);
  }

  @override
  void dispose() {
    _autoSaveSub?.cancel();
    _docSub?.cancel();
    _dirty.close();
    _stopwatch.stop();
    _titleController.dispose();
    _editorFocus.dispose();
    _wordCount.dispose();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Back is a normal way to leave the editor, so it finalizes the entry
        // exactly like Done does. Leaving it as a draft would hide it from
        // streaks, calendar dots and stats, which all skip drafts.
        if (_isEmpty) {
          await _discardIfEmpty();
        } else {
          await _persist(draft: false);
        }
        if (!mounted) return;
        Navigator.of(this.context).pop();
      },
      child: Scaffold(
        backgroundColor: t.page,
        appBar: AppBar(
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
            IconButton(
              tooltip: 'Start from a template',
              icon: const Icon(Icons.article_outlined, size: 20),
              onPressed: _pickTemplate,
            ),
            IconButton(
              tooltip: 'Add a photo',
              icon: const Icon(Icons.image_outlined, size: 20),
              onPressed: _attachImage,
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
        body: Column(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The date reads as a letterhead on the page, and tapping it
                  // is how an old memory gets filed under the day it happened.
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
                        DateFormat('d MMMM yyyy').format(_entryDate).toUpperCase(),
                        style: theme.textTheme.utility.copyWith(color: t.inkDim),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                    child: TextField(
                      controller: _titleController,
                      style: theme.textTheme.displayMedium,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Title',
                        hintStyle: theme.textTheme.displayMedium!
                            .copyWith(color: t.inkFaint),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                  _TagRow(tags: _tags, onEdit: _editTags),
                  if (_entryId != null) _AttachmentStrip(entryId: _entryId!),
                  Expanded(
                    // Quill derives every style from the ambient DefaultTextStyle,
                    // so the reading face is set once here rather than per block.
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyLarge!,
                      child: QuillEditor.basic(
                        controller: quill,
                        focusNode: _editorFocus,
                        config: QuillEditorConfig(
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
            _MoodStrip(
              mood: _mood,
              onChanged: (m) {
                setState(() => _mood = m);
                _dirty.add(null);
              },
            ),
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
                                borderRadius: Radii.chip),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _StatusBar(
                wordCount: _wordCount,
                writingSeconds: _savedWritingSeconds,
                stopwatch: _stopwatch,
                lastSavedAt: _lastSavedAt),
          ],
        ),
      ),
    );
  }
}

/// Which notebook this entry belongs to.
class _JournalPicker extends StatelessWidget {
  const _JournalPicker(
      {required this.journals, required this.journalId, required this.onChanged});

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
            child: Row(children: [
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
            ]),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
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
              child: Text(current.name.toUpperCase(),
                  style: text.utility.copyWith(color: t.inkDim),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
          Icon(Icons.expand_more, size: 16, color: t.inkFaint),
        ]),
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
                child: Text('#${tag.name}',
                    style: text.meta.copyWith(color: t.inkDim)),
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
              label: Text(tags.isEmpty ? 'Add tags' : 'Edit tags',
                  style: text.meta.copyWith(color: t.inkDim)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentStrip extends ConsumerWidget {
  const _AttachmentStrip({required this.entryId});
  final int entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final service = ref.watch(attachmentServiceProvider);
    return StreamBuilder<List<Attachment>>(
      stream: db.watchAttachments(entryId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
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
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _showFull(context, file, () async {
                        await db.removeAttachment(a.id);
                        await service.deleteFile(a.fileName);
                      }),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(file,
                            width: 76, height: 76, fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showFull(BuildContext context, File file, Future<void> Function() onDelete) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.file(file, fit: BoxFit.contain)),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
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
                child: const Text('Close')),
          ]),
        ]),
      ),
    );
  }
}

/// The foot of the editor: what you have written, how long you have been at
/// it, and whether it is safely on disk.
///
/// The save state is the point of this strip. Auto-save is the one thing in the
/// app that happens without being asked, so it says so in words rather than
/// leaving the person to trust a spinner.
class _StatusBar extends StatelessWidget {
  const _StatusBar(
      {required this.wordCount,
      required this.writingSeconds,
      required this.stopwatch,
      required this.lastSavedAt});
  final ValueNotifier<int> wordCount;
  final int writingSeconds;
  final Stopwatch stopwatch;
  final DateTime? lastSavedAt;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final style = text.utility;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
      decoration: BoxDecoration(
        color: t.ground,
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: Row(children: [
        ValueListenableBuilder<int>(
          valueListenable: wordCount,
          builder: (context, count, _) =>
              Text(formatWords(count).toUpperCase(), style: style),
        ),
        const SizedBox(width: 14),
        Text(
          formatTotalTime(writingSeconds + stopwatch.elapsed.inSeconds)
              .toUpperCase(),
          style: style,
        ),
        const Spacer(),
        AnimatedSwitcher(
          duration: Motion.quick,
          child: Text(
            lastSavedAt == null
                ? 'NOT SAVED YET'
                : 'SAVED ${DateFormat.Hm().format(lastSavedAt!)}',
            key: ValueKey(lastSavedAt),
            style: style.copyWith(
                color: lastSavedAt == null ? t.inkFaint : t.inkDim),
          ),
        ),
      ]),
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
  late final Set<int> _selectedIds =
      widget.selected.map((t) => t.id).toSet();
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
      if (!_all.any((t) => t.id == id)) _all = [..._all, Tag(id: id, name: name)];
      _selectedIds.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _newTagController,
            decoration: InputDecoration(
              hintText: 'New tag…',
              suffixIcon: IconButton(
                  icon: const Icon(Icons.add), onPressed: _createTag),
            ),
            onSubmitted: (_) => _createTag(),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in _all)
                  FilterChip(
                    label: Text('#${t.name}'),
                    selected: _selectedIds.contains(t.id),
                    onSelected: (sel) => setState(() =>
                        sel ? _selectedIds.add(t.id) : _selectedIds.remove(t.id)),
                  ),
              ]),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context,
              _all.where((t) => _selectedIds.contains(t.id)).toList()),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
