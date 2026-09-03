import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../data/database.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/entry_row.dart';
import '../widgets/nav_bar.dart';
import 'editor_screen.dart';

/// The month, and what is under a given day.
///
/// `table_calendar` ships a Material-blue grid; every colour here is replaced.
/// The marker under a day with entries used to be the accent, which meant the
/// accent marked "any day at all" — it now marks only today, in one place, and
/// the days that have writing are shown by ink dots.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final monthKey = DateTime(_focusedMonth.year, _focusedMonth.month);
    final counts = ref.watch(monthCountsProvider(monthKey)).value ?? const {};
    final dayKey = localDay(_selectedDay);
    final dayEntries = ref.watch(entriesOnDayProvider(dayKey));
    final isToday = dayOrdinal(dayKey) == dayOrdinal(DateTime.now());

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Row(children: [
              Expanded(
                child: Text(DateFormat('MMMM yyyy').format(_focusedMonth),
                    style: text.displayMedium),
              ),
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left, size: 22),
                onPressed: () => setState(() => _focusedMonth =
                    DateTime(_focusedMonth.year, _focusedMonth.month - 1)),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right, size: 22),
                onPressed: () => setState(() => _focusedMonth =
                    DateTime(_focusedMonth.year, _focusedMonth.month + 1)),
              ),
            ]),
          ),
          TableCalendar<void>(
            firstDay: DateTime(2000),
            lastDay: DateTime.now().add(const Duration(days: 366)),
            focusedDay: _focusedMonth,
            selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
            onDaySelected: (selected, focused) => setState(() {
              _selectedDay = selected;
              _focusedMonth = focused;
            }),
            onPageChanged: (focused) => setState(() => _focusedMonth = focused),
            headerVisible: false,
            daysOfWeekHeight: 26,
            rowHeight: 44,
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: text.utility,
              weekendStyle: text.utility,
            ),
            calendarStyle: const CalendarStyle(outsideDaysVisible: false),
            // Every cell is drawn here rather than through CalendarStyle.
            // table_calendar stretches its decoration to the full cell, which
            // made the selected day a wide lozenge across a seventh of the
            // screen; a date wants a square.
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, _) => _DayCell(
                  day: day, count: counts[localDay(day)] ?? 0),
              outsideBuilder: (context, day, _) => const SizedBox.shrink(),
              disabledBuilder: (context, day, _) => _DayCell(
                  day: day, count: 0, muted: true),
              todayBuilder: (context, day, _) => _DayCell(
                day: day,
                count: counts[localDay(day)] ?? 0,
                isToday: true,
                isSelected: isSameDay(day, _selectedDay),
              ),
              selectedBuilder: (context, day, _) => _DayCell(
                day: day,
                count: counts[localDay(day)] ?? 0,
                isToday: dayOrdinal(day) == dayOrdinal(DateTime.now()),
                isSelected: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.hairline)),
            ),
            child: Text(
              isToday
                  ? 'TODAY'
                  : DateFormat('EEEE d MMMM').format(dayKey).toUpperCase(),
              style: text.utility
                  .copyWith(color: isToday ? t.accent : t.inkDim),
            ),
          ),
          Expanded(
            child: dayEntries.when(
              loading: () => const SizedBox.shrink(),
              error: (e, st) {
                debugPrint('day query failed: $e\n$st');
                return _DayMessage(
                  title: "Couldn't read this day",
                  body: 'Your entries are still on this device. '
                      'Pick another day, or reopen the app.',
                );
              },
              data: (entries) => entries.isEmpty
                  ? _DayMessage(
                      title: isToday
                          ? 'Nothing written today'
                          : 'Nothing written on this day',
                      body: isToday
                          ? 'Write now and it is filed under today.'
                          : 'Anything you write here is filed under this date, '
                              'however long ago it was.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(left: 20, bottom: 96),
                      itemCount: entries.length,
                      itemBuilder: (context, i) => EntryRow(entry: entries[i]),
                    ),
            ),
          ),
        ]),
      ),
      floatingActionButton: WriteButton(
        label: isToday ? 'Write' : 'Write here',
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EditorScreen(initialDate: dayKey))),
      ),
    );
  }
}

/// One day in the grid.
///
/// Today is the accent wherever it appears — filled when it is also the
/// selected day, a ring when the selection has moved elsewhere. Selecting some
/// other day fills it with ink. That keeps the rule the rest of the app follows:
/// the accent means today, and nothing else on this screen is allowed to use it.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    this.isToday = false,
    this.isSelected = false,
    this.muted = false,
  });

  final DateTime day;
  final int count;
  final bool isToday;
  final bool isSelected;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;

    final fill = isSelected ? (isToday ? t.accent : t.ink) : null;
    final border = !isSelected && isToday ? t.accent : null;
    final label = isSelected
        ? t.ground
        : muted
            ? t.hairline
            : isToday
                ? t.accent
                : t.ink;

    return Center(
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: Radii.chip,
          border: border == null ? null : Border.all(color: border, width: 1.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${day.day}',
              style: text.bodySmall!.copyWith(
                color: label,
                fontWeight:
                    isToday || isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (count > 0)
              Positioned(
                bottom: 5,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < (count > 3 ? 3 : count); i++)
                    Container(
                      width: 3,
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? t.ground : t.spineWeight,
                        shape: BoxShape.circle,
                      ),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayMessage extends StatelessWidget {
  const _DayMessage({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(body, style: text.bodySmall),
          ),
        ],
      ),
    );
  }
}
