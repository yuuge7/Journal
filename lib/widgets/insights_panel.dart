import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import '../providers.dart';
import '../screens/editor_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'formatting.dart';
import 'mood_meter.dart';

class InsightsPanel extends ConsumerWidget {
  const InsightsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(insightsProvider).value ?? <EntryInsight>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    final journals = ref.watch(allJournalsProvider).value ?? [];
    final hours = List<int>.filled(24, 0);
    for (final e in rows) {
      hours[e.createdAt.hour]++;
    }
    final sameDay = rows
        .where(
          (e) =>
              dayOrdinal(e.entryDate) ==
              dayOrdinal(e.createdAt) -
                  (e.createdAt.hour < (ref.watch(dayEndsAtProvider).value ?? 0)
                      ? 1
                      : 0),
        )
        .length;
    final longest = rows.reduce((a, b) => a.wordCount >= b.wordCount ? a : b);
    final longestSession = rows.reduce(
      (a, b) => a.writingSeconds >= b.writingSeconds ? a : b,
    );
    final moods = rows.where((e) => e.mood != null).toList();
    final seconds = rows.fold<int>(0, (s, e) => s + e.writingSeconds);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(label, style: text.utility),
    );
    Widget record(String label, EntryInsight e, String value) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(e.title.isEmpty ? 'Untitled entry' : e.title),
      trailing: Text(value),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => EditorScreen(entryId: e.id))),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('WHEN YOU WRITE'),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var hour = 0; hour < 24; hour++)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${hour.toString().padLeft(2, '0')}:00 · ${hours[hour]} entries',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height:
                            3 +
                            hours[hour] /
                                math.max(1, hours.reduce(math.max)) *
                                78,
                        color: t.spineWeight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('00'),
              Text('06'),
              Text('12'),
              Text('18'),
              Text('23'),
            ],
          ),
          heading('BY NOTEBOOK'),
          for (final j in journals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('${j.emoji} ${j.name}', style: text.titleSmall),
                  Text(
                    '${formatNumber(rows.where((e) => e.journalId == j.id).fold<int>(0, (s, e) => s + e.wordCount))} words · ${formatTotalTime(rows.where((e) => e.journalId == j.id).fold<int>(0, (s, e) => s + e.writingSeconds))}',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          heading('THE DAY LIVED, THE DAY WRITTEN'),
          Text(
            '${((rows.length - sameDay) * 100 / rows.length).round()}% backfilled',
            style: text.displaySmall,
          ),
          Text(
            '$sameDay of ${rows.length} entries were written on the day they belong to.',
            style: text.bodySmall,
          ),
          heading('MOOD OVER TIME'),
          if (moods.isEmpty)
            const Text('Choose a mood in an entry to start this view.')
          else ...[
            Semantics(
              label:
                  'Mood history, oldest to newest, ${moods.length} observations',
              child: SizedBox(
                height: 70,
                width: double.infinity,
                child: CustomPaint(
                  painter: MoodHistoryPainter(
                    values: moods.map((e) => e.mood!.toDouble()).toList(),
                    color: t.inkDim,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (var m = 1; m <= 5; m++)
              if (moods.any((e) => e.mood == m))
                Text(
                  '${moodLabel(m)} · ${(moods.where((e) => e.mood == m).fold<int>(0, (s, e) => s + e.wordCount) / moods.where((e) => e.mood == m).length).round()} words on average',
                  style: text.bodySmall,
                ),
          ],
          heading('PERSONAL RECORDS'),
          record('Longest entry', longest, formatWords(longest.wordCount)),
          record(
            'Most time at the page',
            longestSession,
            formatTotalTime(longestSession.writingSeconds),
          ),
          heading('MILESTONES'),
          for (final n in [1, 10, 50, 100, 500, 1000])
            if (rows.length >= n)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('$n entries kept', style: text.bodySmall),
              ),
          for (final h in [1, 10, 50, 100])
            if (seconds >= h * 3600)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('$h hours at the page', style: text.bodySmall),
              ),
        ],
      ),
    );
  }
}

class MoodHistoryPainter extends CustomPainter {
  const MoodHistoryPainter({required this.values, required this.color});
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : i / (values.length - 1) * size.width;
      final y = size.height - 5 - (values[i] - 1) / 4 * (size.height - 10);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = color);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MoodHistoryPainter oldDelegate) =>
      values != oldDelegate.values || color != oldDelegate.color;
}
