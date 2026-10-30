import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/database.dart';
import '../providers.dart';
import '../theme/tokens.dart';

Future<DateTime?> showYearJump(BuildContext context) =>
    showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const YearGrid(),
    );

class YearGrid extends ConsumerStatefulWidget {
  const YearGrid({super.key});
  @override
  ConsumerState<YearGrid> createState() => _YearGridState();
}

class _YearGridState extends ConsumerState<YearGrid> {
  int year = DateTime.now().year;
  @override
  Widget build(BuildContext context) {
    final heat = ref.watch(heatProvider(year)).value ?? {};
    final t = context.tokens;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous year',
                  onPressed: year <= 2000 ? null : () => setState(() => year--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '$year · time at the page',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Next year',
                  onPressed: year > DateTime.now().year
                      ? null
                      : () => setState(() => year++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Darker days mean more writing. Tap a month.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:
                      MediaQuery.sizeOf(context).width < 350 ||
                          MediaQuery.textScalerOf(context).scale(14) > 22
                      ? 2
                      : 3,
                  childAspectRatio: .85,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: 12,
                itemBuilder: (context, i) {
                  final month = i + 1;
                  final first = DateTime(year, month);
                  final length = DateTime(year, month + 1, 0).day;
                  return Semantics(
                    button: true,
                    label: DateFormat.yMMMM().format(first),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, first),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat.MMM().format(first),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: GridView.count(
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 7,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                              children: [
                                for (
                                  var slot = 0;
                                  slot < first.weekday - 1 + length;
                                  slot++
                                )
                                  Builder(
                                    builder: (_) {
                                      final day = DateTime(
                                        year,
                                        month,
                                        slot - first.weekday + 2,
                                      );
                                      final seconds = heat[localDay(day)];
                                      return Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            1,
                                          ),
                                          color: slot < first.weekday - 1
                                              ? Colors.transparent
                                              : seconds == null
                                              ? t.hairline.withValues(
                                                  alpha: .45,
                                                )
                                              : Color.lerp(
                                                  t.spine,
                                                  t.spineWeight,
                                                  (.2 + seconds / 2700).clamp(
                                                    0,
                                                    1,
                                                  ),
                                                ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
