import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../providers.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'bin_screen.dart';
import 'editor_screen.dart';

const _palette = Palette.journalColors;
const _emojis = ['📔', '💼', '✈️', '💪', '🎨', '❤️', '🌱', '🧠', '🍳', '🎓'];

class JournalsScreen extends ConsumerWidget {
  const JournalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journals = ref.watch(allJournalsProvider).value ?? const <Journal>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journals'),
        actions: [
          IconButton(
            tooltip: 'Recently deleted',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BinScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        onReorderItem: (oldIndex, newIndex) async {
          final ids = journals.map((j) => j.id).toList();
          ids.insert(newIndex, ids.removeAt(oldIndex));
          await ref.read(databaseProvider).reorderJournals(ids);
        },
        itemCount: journals.length,
        itemBuilder: (context, i) {
          final j = journals[i];
          final entries =
              (ref.watch(insightsProvider).value ?? <EntryInsight>[])
                  .where((e) => e.journalId == j.id)
                  .toList();
          final last = entries.isEmpty
              ? null
              : entries
                    .map((e) => e.updatedAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b);
          return Container(
            key: ValueKey(j.id),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.tokens.hairline),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    j.emoji,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 4),
                  Container(width: 6, height: 6, color: Color(j.color)),
                ],
              ),
              title: Text(j.name),
              subtitle: Text(
                '${entries.length} entries \u00b7 ${entries.fold<int>(0, (s, e) => s + e.wordCount)} words${j.archived ? " \u00b7 archived" : ""}\n${last == null ? "No writing yet" : "Last written ${last.toString().substring(0, 10)}"}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  final db = ref.read(databaseProvider);
                  if (action == 'edit') await _edit(context, ref, j);
                  if (action == 'write' && context.mounted) {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditorScreen(journalId: j.id),
                      ),
                    );
                  }
                  if (action == 'archive') {
                    await db.archiveJournal(j.id, !j.archived);
                    ref.read(selectedJournalProvider.notifier).select(null);
                  }
                  if (action == 'delete' && context.mounted) {
                    await _confirmDelete(context, ref, j);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'write',
                    child: Text('Write here'),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit notebook'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    enabled:
                        j.archived ||
                        journals.where((j) => !j.archived).length > 1,
                    child: Text(j.archived ? 'Unarchive' : 'Archive'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled:
                        journals.where((j) => !j.archived).length > 1 ||
                        j.archived,
                    child: const Text('Move to recently deleted'),
                  ),
                ],
              ),
              onTap: () => _edit(context, ref, j),
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Journal? journal,
  ) async {
    final result = await showDialog<(String, int, String)>(
      context: context,
      builder: (context) => _JournalDialog(journal: journal),
    );
    if (result == null) return;
    final db = ref.read(databaseProvider);
    if (journal == null) {
      await db.createJournal(result.$1, result.$2, result.$3);
    } else {
      await db.renameJournal(journal.id, result.$1, result.$2, result.$3);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Journal journal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${journal.name}"?'),
        content: const Text(
          'The notebook and its entries can be restored from Recently deleted for 30 days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (ref.read(selectedJournalProvider) == journal.id) {
        ref.read(selectedJournalProvider.notifier).select(null);
      }
      final db = ref.read(databaseProvider);
      await db.deleteJournal(journal.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notebook moved to recently deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => db.restoreJournal(journal.id),
            ),
          ),
        );
      }
    }
  }
}

class _JournalDialog extends StatefulWidget {
  const _JournalDialog({this.journal});
  final Journal? journal;

  @override
  State<_JournalDialog> createState() => _JournalDialogState();
}

class _JournalDialogState extends State<_JournalDialog> {
  late final _nameController = TextEditingController(
    text: widget.journal?.name ?? '',
  );
  late int _color = widget.journal?.color ?? _palette.first;
  late String _emoji = widget.journal?.emoji ?? _emojis.first;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.journal == null ? 'New journal' : 'Edit journal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 64,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _emojis)
                  ChoiceChip(
                    label: Text(e),
                    selected: _emoji == e,
                    onSelected: (_) => setState(() => _emoji = e),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: _color == c
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
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
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, (name, _color, _emoji));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
