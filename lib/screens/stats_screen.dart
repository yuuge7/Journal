import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../providers.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streaks = ref.watch(streaksProvider).value ??
        const StreakInfo(current: 0, longest: 0);
    final stats = ref.watch(globalStatsProvider).value;
    final activity = ref.watch(activityProvider).value ?? const <DayCount>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StreakCard(streaks: streaks),
          const SizedBox(height: 12),
          if (stats != null)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.9,
              children: [
                _StatTile(
                    icon: Icons.article_outlined,
                    value: '${stats.totalEntries}',
                    label: 'Entries'),
                _StatTile(
                    icon: Icons.notes_outlined,
                    value: _compact(stats.totalWords),
                    label: 'Words written'),
                _StatTile(
                    icon: Icons.timer_outlined,
                    value: _fmtTime(stats.totalWritingSeconds),
                    label: 'Time writing'),
                _StatTile(
                    icon: Icons.image_outlined,
                    value: '${stats.totalAttachments}',
                    label: 'Photos'),
                _StatTile(
                    icon: Icons.speed_outlined,
                    value: stats.avgWordsPerEntry.toStringAsFixed(0),
                    label: 'Avg words / entry'),
              ],
            ),
          const SizedBox(height: 16),
          Text('Last 30 days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _ActivityChart(activity: activity),
        ],
      ),
    );
  }

  static String _compact(int n) =>
      NumberFormat.compact().format(n);

  static String _fmtTime(int seconds) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${seconds}s';
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streaks});
  final StreakInfo streaks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          const Text('🔥', style: TextStyle(fontSize: 44)),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${streaks.current} day streak',
                style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold)),
            Text('Longest: ${streaks.longest} days',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer)),
          ]),
        ]),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  child: Text(value,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text(label,
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Simple bar strip: one bar per day of the last 30 days.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.activity});
  final List<DayCount> activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDay = {
      for (final d in activity)
        DateTime(d.day.year, d.day.month, d.day.day): d.count
    };
    final today = DateTime.now();
    final days = [
      for (var i = 29; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i)
    ];
    final maxCount =
        activity.isEmpty ? 1 : activity.map((d) => d.count).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: byDay[day] == null
                          ? 4
                          : 12 + 60 * (byDay[day]! / maxCount),
                      decoration: BoxDecoration(
                        color: byDay[day] == null
                            ? theme.colorScheme.surfaceContainerHighest
                            : theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
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
