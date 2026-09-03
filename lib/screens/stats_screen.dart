import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/formatting.dart';

/// What the writing adds up to.
///
/// The old screen was a stack of Material cards with a 🔥 emoji at the top and
/// every icon tinted with the theme's primary. It has the same numbers now, but
/// they are set as figures rather than decorated: one column of measured rows,
/// and the accent spent only where it means today.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final streaks = ref.watch(streaksProvider).value;
    final stats = ref.watch(globalStatsProvider).value;
    final activity = ref.watch(activityProvider).value ?? const <DayCount>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Text('Your writing', style: text.displayLarge),
            ),
            const SizedBox(height: 22),
            if (streaks == null || stats == null)
              const _StatsLoading()
            else if (stats.totalEntries == 0)
              const _StatsEmpty()
            else ...[
              _StreakBlock(streaks: streaks),
              const SizedBox(height: 8),
              _Figures(stats: stats),
              const SizedBox(height: 28),
              _ActivityChart(activity: activity),
            ],
          ],
        ),
      ),
    );
  }
}

/// The streak, given the space it earns: it is the number people open this
/// screen for. Live streaks carry the accent because a live streak *is* today.
class _StreakBlock extends StatelessWidget {
  const _StreakBlock({required this.streaks});
  final StreakInfo streaks;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final alive = streaks.current > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.hairline),
          bottom: BorderSide(color: t.hairline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CURRENT STREAK', style: text.utility),
                const SizedBox(height: 6),
                Text(
                  '${streaks.current}',
                  style: text.displayLarge!.copyWith(
                    fontSize: 44,
                    height: 1,
                    color: alive ? t.accent : t.inkFaint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alive
                      ? (streaks.current == 1 ? 'day in a row' : 'days in a row')
                      : 'write today to start one',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('LONGEST', style: text.utility),
              const SizedBox(height: 6),
              Text(
                '${streaks.longest}',
                style: text.displayLarge!.copyWith(fontSize: 30, height: 1),
              ),
              const SizedBox(height: 4),
              Text(streaks.longest == 1 ? 'day' : 'days', style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// One measured row per fact. A grid of tiles turned five different units into
/// five identical boxes; a list lets the numbers line up in a column and be
/// compared, which is what they are for.
class _Figures extends StatelessWidget {
  const _Figures({required this.stats});
  final GlobalStats stats;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Entries', '${stats.totalEntries}'),
      ('Words written', formatNumber(stats.totalWords)),
      ('Time at the page', formatTotalTime(stats.totalWritingSeconds)),
      ('Words per entry, on average', stats.avgWordsPerEntry.round().toString()),
      ('Photos kept', '${stats.totalAttachments}'),
    ];
    return Column(
      children: [for (final (label, value) in rows) _FigureRow(label: label, value: value)],
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(label, style: text.bodySmall!.copyWith(color: t.inkDim))),
          const SizedBox(width: 16),
          Text(value, style: text.displaySmall!.copyWith(fontSize: 20)),
        ],
      ),
    );
  }
}

/// One bar per day for the last 30. Today is the accent; every other day is
/// ink. Days with nothing get a stub so the gaps stay visible — the same
/// argument as the spine in the feed.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.activity});
  final List<DayCount> activity;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final byDay = {for (final d in activity) localDay(d.day): d.count};
    final today = DateTime.now();
    final days = [
      for (var i = 29; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i)
    ];
    final maxCount = activity.isEmpty
        ? 1
        : activity.map((d) => d.count).reduce((a, b) => a > b ? a : b);
    final written = days.where((d) => byDay.containsKey(d)).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('LAST 30 DAYS', style: text.utility),
            const Spacer(),
            Text('$written OF 30 WRITTEN', style: text.utility),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 76,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        height: byDay[day] == null
                            ? 3
                            : 10 + 62 * (byDay[day]! / maxCount),
                        decoration: BoxDecoration(
                          color: byDay[day] == null
                              ? t.hairline
                              : (dayOrdinal(day) == dayOrdinal(today)
                                  ? t.accent
                                  : t.spineWeight),
                          borderRadius:
                              const BorderRadius.all(Radius.circular(1.5)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text(DateFormat('d MMM').format(days.first).toUpperCase(),
                style: text.utility),
            const Spacer(),
            Text('TODAY', style: text.utility.copyWith(color: t.accent)),
          ]),
        ],
      ),
    );
  }
}

class _StatsLoading extends StatelessWidget {
  const _StatsLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator()),
        const SizedBox(width: 12),
        Text('COUNTING', style: Theme.of(context).textTheme.utility),
      ]),
    );
  }
}

class _StatsEmpty extends StatelessWidget {
  const _StatsEmpty();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing to count yet', style: text.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Streaks, word counts and time at the page start the moment you '
            'finish your first entry.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
