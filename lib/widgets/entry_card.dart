import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../providers.dart';
import '../screens/editor_screen.dart';

/// Time spent writing an entry, shortened for the feed: `45s`, `12m`, `2h 5m`.
String formatWritingTime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

class EntryCard extends ConsumerWidget {
  const EntryCard({super.key, required this.entry, this.showYear = false});

  final Entry entry;
  final bool showYear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tags = ref.watch(tagsByEntryProvider).value?[entry.id] ?? const <Tag>[];
    final thumbName = ref.watch(thumbnailsProvider).value?[entry.id];
    final journals = ref.watch(journalsProvider).value ?? const <Journal>[];
    final journal = journals.where((j) => j.id == entry.journalId).firstOrNull;

    final preview = entry.plainText
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EditorScreen(entryId: entry.id))),
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (journal != null) ...[
                        Text(journal.emoji,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(journal.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: Color(journal.color))),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        DateFormat(showYear ? 'MMM d, yyyy' : 'EEE, MMM d')
                            .format(entry.entryDate),
                        style: theme.textTheme.labelSmall,
                      ),
                      if (entry.mood != null) ...[
                        const SizedBox(width: 6),
                        Text(moodEmojis[entry.mood! - 1],
                            style: const TextStyle(fontSize: 13)),
                      ],
                      if (entry.isDraft) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Draft',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      theme.colorScheme.onTertiaryContainer)),
                        ),
                      ],
                    ]),
                    if (entry.title.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(entry.title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, children: [
                        for (final t in tags)
                          Text('#${t.name}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary)),
                      ]),
                    ],
                    const SizedBox(height: 6),
                    Text(
                        entry.writingSeconds > 0
                            ? '${entry.wordCount} words  ·  ✍ ${formatWritingTime(entry.writingSeconds)}'
                            : '${entry.wordCount} words',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline)),
                  ],
                ),
              ),
              if (thumbName != null) ...[
                const SizedBox(width: 10),
                _Thumb(fileName: thumbName),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This cannot be undone.'),
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
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    final service = ref.read(attachmentServiceProvider);
    for (final a in await db.attachmentsForEntry(entry.id)) {
      await service.deleteFile(a.fileName);
    }
    await db.deleteEntry(entry.id);
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.fileName});
  final String fileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<File>(
      future: ref.read(attachmentServiceProvider).fileFor(fileName),
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return const SizedBox(width: 64, height: 64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(file, width: 64, height: 64, fit: BoxFit.cover),
        );
      },
    );
  }
}
