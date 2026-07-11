import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../providers.dart';

const _palette = [
  0xFF6750A4, 0xFF1E88E5, 0xFF43A047, 0xFFF4511E,
  0xFFD81B60, 0xFF00897B, 0xFF7B1FA2, 0xFFF9A825,
];
const _emojis = ['📔', '💼', '✈️', '💪', '🎨', '❤️', '🌱', '🧠', '🍳', '🎓'];

class JournalsScreen extends ConsumerWidget {
  const JournalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journals = ref.watch(journalsProvider).value ?? const <Journal>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Journals')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: journals.length,
        itemBuilder: (context, i) {
          final j = journals[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(j.color).withValues(alpha: 0.2),
              child: Text(j.emoji),
            ),
            title: Text(j.name),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: journals.length <= 1
                  ? null
                  : () => _confirmDelete(context, ref, j),
            ),
            onTap: () => _edit(context, ref, j),
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Journal? journal) async {
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
      BuildContext context, WidgetRef ref, Journal journal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${journal.name}"?'),
        content:
            const Text('All entries in this journal will be deleted too.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      if (ref.read(selectedJournalProvider) == journal.id) {
        ref.read(selectedJournalProvider.notifier).select(null);
      }
      await ref.read(databaseProvider).deleteJournal(journal.id);
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
  late final _nameController =
      TextEditingController(text: widget.journal?.name ?? '');
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
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in _emojis)
            ChoiceChip(
              label: Text(e),
              selected: _emoji == e,
              onSelected: (_) => setState(() => _emoji = e),
            ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _palette)
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Color(c),
                child: _color == c
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
        ]),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
