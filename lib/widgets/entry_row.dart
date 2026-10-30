import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../providers.dart';
import '../screens/editor_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'formatting.dart';
import 'mood_meter.dart';

/// One entry in a list.
///
/// Not a Card any more. The feed used to be a stack of elevated rounded
/// rectangles with the date repeated on every one of them; the date now lives
/// once per day on the spine, and a row is just type on the ground. What is
/// left on the row is only what differs between entries: the title, the opening
/// of the writing, and the three measurements this app actually keeps — words,
/// minutes at the page, and how the day felt.
class EntryRow extends ConsumerWidget {
  const EntryRow({
    super.key,
    required this.entry,
    this.dateLabel,
    this.showJournal = true,
    this.selected = false,
    this.onSelect,
  });

  final Entry entry;

  /// Set where a row is not filed under a day heading (the calendar list, the
  /// throwback strip) and therefore has to carry its own date.
  final String? dateLabel;

  final bool showJournal;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final tags = ref.watch(entryTagsProvider(entry.id)).value ?? const <Tag>[];
    final thumbName = ref.watch(entryThumbProvider(entry.id)).value;
    final journals = ref.watch(journalsProvider).value ?? const <Journal>[];
    final journal = journals.where((j) => j.id == entry.journalId).firstOrNull;

    final query = ref.watch(searchQueryProvider);
    final preview = entryPreview(entry.plainText, query: query);
    final backfill = formatBackfill(
      entry.entryDate,
      entry.createdAt,
      dayEndsAt: ref.watch(dayEndsAtProvider).value ?? 0,
    );
    final hasTitle = entry.title.trim().isNotEmpty;

    return Dismissible(
      key: ValueKey('entry-${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: t.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.all(20),
        child: Icon(Icons.delete_outline, color: t.page),
      ),
      confirmDismiss: (_) async {
        await _delete(context, ref);
        return false;
      },
      child: Semantics(
        button: true,
        label: [
          if (hasTitle) entry.title.trim() else 'Untitled entry',
          dateLabel ?? DateFormat.yMMMMd().format(entry.entryDate),
          formatWords(entry.wordCount),
          if (entry.mood != null) 'mood ${moodLabel(entry.mood!)}',
        ].join(', '),
        excludeSemantics: true,
        onTap:
            onSelect ??
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditorScreen(entryId: entry.id),
              ),
            ),
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Move to recently deleted'): () =>
              _delete(context, ref),
          const CustomSemanticsAction(label: 'Select entry'): ?onSelect,
        },
        child: InkWell(
          onTap:
              onSelect ??
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditorScreen(entryId: entry.id),
                ),
              ),
          onLongPress: () => _delete(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 11, 20, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (onSelect != null)
                        Icon(
                          selected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                        ),
                      // Header row: what this entry *is* — which notebook, which
                      // day, how it felt. The measurements go on their own line
                      // below; mood sat next to them in an earlier pass and read
                      // as a chart of the numbers rather than a separate fact.
                      if (dateLabel != null ||
                          (showJournal && journal != null) ||
                          entry.isDraft ||
                          entry.mood != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 3,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (dateLabel != null)
                                      Text(
                                        dateLabel!.toUpperCase(),
                                        style: text.utility,
                                      ),
                                    if (showJournal && journal != null)
                                      _JournalMark(journal: journal),
                                    if (entry.isDraft) const _DraftMark(),
                                  ],
                                ),
                              ),
                              if (entry.mood != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: MoodMeter(mood: entry.mood!, size: 11),
                                ),
                            ],
                          ),
                        ),
                      if (hasTitle)
                        Text(
                          entry.title.trim(),
                          style: text.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (thumbName != null && entry.wordCount < 12)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          child: _Thumb(fileName: thumbName, wide: true),
                        ),
                      if (preview.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: hasTitle ? 3 : 0),
                          child: Text.rich(
                            highlightedPreview(
                              preview,
                              query,
                              t.accentSoft,
                              t.ink,
                            ),
                            style: hasTitle
                                ? text.bodyMedium
                                : text.bodyMedium!.copyWith(color: t.ink),
                            maxLines: hasTitle ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (!hasTitle && preview.isEmpty)
                        Text(
                          'Empty entry',
                          style: text.bodyMedium!.copyWith(color: t.inkFaint),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: _MetaLine(
                          entry: entry,
                          tags: tags,
                          backfill: backfill,
                        ),
                      ),
                    ],
                  ),
                ),
                if (thumbName != null && entry.wordCount >= 12) ...[
                  const SizedBox(width: 14),
                  _Thumb(fileName: thumbName, wide: entry.wordCount < 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    await db.deleteEntry(entry.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Moved to recently deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => db.restoreEntry(entry.id),
        ),
      ),
    );
  }
}

/// Words, minutes, mood and tags — the row's one measured line.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.entry,
    required this.tags,
    required this.backfill,
  });

  final Entry entry;
  final List<Tag> tags;
  final String? backfill;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final time = formatWritingTime(entry.writingSeconds);
    final facts = <String>[
      formatWords(entry.wordCount),
      if (time.isNotEmpty) time,
      ?backfill,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(facts.join('  ·  '), style: text.meta.copyWith(color: t.inkFaint)),
        for (final tag in tags)
          Text('#${tag.name}', style: text.meta.copyWith(color: t.inkDim)),
      ],
    );
  }
}

/// Which notebook an entry is in. The journal's own colour appears here and in
/// the filter rail, and nowhere else — it marks identity, never importance.
class _JournalMark extends StatelessWidget {
  const _JournalMark({required this.journal});
  final Journal journal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: Color(journal.color),
            borderRadius: const BorderRadius.all(Radius.circular(1.5)),
          ),
        ),
        Text(journal.name.toUpperCase(), style: text.utility),
      ],
    );
  }
}

class _DraftMark extends StatelessWidget {
  const _DraftMark();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message:
          'The editor closed without finishing this entry. '
          'Open it and press Done to count it.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: t.hairline),
          borderRadius: Radii.chip,
        ),
        child: Text(
          'UNFINISHED',
          style: Theme.of(context).textTheme.utility.copyWith(fontSize: 9.5),
        ),
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.fileName, this.wide = false});
  final String fileName;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return FutureBuilder<File>(
      future: ref.read(attachmentServiceProvider).fileFor(fileName),
      builder: (context, snap) {
        final file = snap.data;
        return Container(
          width: wide ? double.infinity : 58,
          height: wide ? 160 : 58,
          decoration: BoxDecoration(
            color: t.pageEdge,
            borderRadius: Radii.chip,
            border: Border.all(color: t.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: file == null
              ? null
              : Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    // A photo whose file went missing must not blow up the feed.
                    return Icon(
                      Icons.image_not_supported_outlined,
                      size: 18,
                      color: t.inkFaint,
                    );
                  },
                ),
        );
      },
    );
  }
}
