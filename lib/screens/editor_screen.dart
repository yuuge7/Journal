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
import '../widgets/template_sheet.dart';

const moodEmojis = ['😞', '😕', '😐', '🙂', '😄'];

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
    _docSub = _quill!.document.changes.listen((_) {
      _recountWords();
      _dirty.add(null);
    });
    _titleController.addListener(() => _dirty.add(null));
    _autoSaveSub = _dirty
        .debounceTime(const Duration(seconds: 2))
        .listen((_) => _persist(draft: _isDraft));

    // Offer templates when starting a brand-new entry.
    if (widget.entryId == null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickTemplate());
    }
  }

  void _recountWords() {
    final text = _quill!.document.toPlainText().trim();
    _wordCount.value =
        text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
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

    final plain = _quill!.document.toPlainText().trim();
    final companion = EntriesCompanion(
      journalId: Value(_journalId!),
      title: Value(_titleController.text.trim()),
      contentJson: Value(jsonEncode(_quill!.document.toDelta().toJson())),
      plainText: Value(plain),
      entryDate: Value(_entryDate),
      updatedAt: Value(DateTime.now()),
      wordCount: Value(_wordCount.value),
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
        wordCount: Value(_wordCount.value),
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
        appBar: AppBar(
          title: TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event, size: 18),
            label: Text(DateFormat.yMMMd().format(_entryDate)),
          ),
          actions: [
            IconButton(
              tooltip: 'Templates',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: _pickTemplate,
            ),
            IconButton(
              tooltip: 'Attach image',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _attachImage,
            ),
            FilledButton.tonal(
              onPressed: _saveAndClose,
              child: const Text('Done'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                if (journals.isNotEmpty)
                  DropdownButton<int>(
                    value: _journalId,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final j in journals)
                        DropdownMenuItem(
                            value: j.id, child: Text('${j.emoji} ${j.name}'))
                    ],
                    onChanged: (v) {
                      setState(() => _journalId = v);
                      _dirty.add(null);
                    },
                  ),
                const Spacer(),
                for (var i = 0; i < moodEmojis.length; i++)
                  GestureDetector(
                    onTap: () {
                      setState(() => _mood = _mood == i + 1 ? null : i + 1);
                      _dirty.add(null);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _mood == null || _mood == i + 1 ? 1 : 0.3,
                        child: Text(moodEmojis[i],
                            style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _titleController,
                style: theme.textTheme.headlineSmall,
                decoration: const InputDecoration(
                    hintText: 'Title', border: InputBorder.none),
              ),
            ),
            _TagRow(tags: _tags, onEdit: _editTags),
            if (_entryId != null) _AttachmentStrip(entryId: _entryId!),
            const Divider(height: 1),
            Expanded(
              child: QuillEditor.basic(
                controller: quill,
                focusNode: _editorFocus,
                config: const QuillEditorConfig(
                  placeholder: 'Start writing…',
                  padding: EdgeInsets.all(16),
                ),
              ),
            ),
            const Divider(height: 1),
            QuillSimpleToolbar(
              controller: quill,
              config: const QuillSimpleToolbarConfig(
                multiRowsDisplay: false,
                showFontFamily: false,
                showFontSize: false,
                showSubscript: false,
                showSuperscript: false,
                showSearchButton: false,
                showAlignmentButtons: false,
                showIndent: false,
                showDividers: false,
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

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags, required this.onEdit});
  final List<Tag> tags;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          ActionChip(
            avatar: const Icon(Icons.sell_outlined, size: 16),
            label: Text(tags.isEmpty ? 'Add tags' : 'Tags'),
            onPressed: onEdit,
          ),
          const SizedBox(width: 6),
          for (final t in tags)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Chip(
                  label: Text('#${t.name}'),
                  visualDensity: VisualDensity.compact),
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
    final style = Theme.of(context).textTheme.labelSmall;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(children: [
        ValueListenableBuilder<int>(
          valueListenable: wordCount,
          builder: (context, count, _) => Text('$count words', style: style),
        ),
        const SizedBox(width: 16),
        Text(
            '✍ ${_fmtDuration(writingSeconds + stopwatch.elapsed.inSeconds)}',
            style: style),
        const Spacer(),
        Text(
          lastSavedAt == null
              ? 'Not saved yet'
              : 'Saved ${DateFormat.Hm().format(lastSavedAt!)}',
          style: style,
        ),
      ]),
    );
  }

  static String _fmtDuration(int seconds) {
    final m = seconds ~/ 60, s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
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
