import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../providers.dart';
import '../widgets/entry_card.dart';
import 'editor_screen.dart';

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
    final theme = Theme.of(context);
    final monthKey = DateTime(_focusedMonth.year, _focusedMonth.month);
    final counts = ref.watch(monthCountsProvider(monthKey)).value ?? {};
    final dayKey =
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    final dayEntries = ref.watch(entriesOnDayProvider(dayKey));

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Write for this day',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EditorScreen(initialDate: dayKey))),
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(children: [
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
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          headerStyle: const HeaderStyle(
              formatButtonVisible: false, titleCentered: true),
          calendarBuilders: CalendarBuilders(
            // Dot marker on days that contain entries.
            markerBuilder: (context, day, _) {
              final count =
                  counts[DateTime(day.year, day.month, day.day)] ?? 0;
              if (count == 0) return null;
              return Positioned(
                bottom: 4,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < (count > 3 ? 3 : count); i++)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ]),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: dayEntries.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) => entries.isEmpty
                ? Center(
                    child: Text('Nothing written on this day',
                        style: theme.textTheme.bodyMedium))
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 80),
                    itemCount: entries.length,
                    itemBuilder: (context, i) =>
                        EntryCard(entry: entries[i], showYear: true),
                  ),
          ),
        ),
      ]),
    );
  }
}
