import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';
import 'package:journal/providers.dart';
import 'package:journal/screens/feed_screen.dart';
import 'package:journal/screens/calendar_screen.dart';
import 'package:journal/screens/stats_screen.dart';
import 'package:journal/screens/settings_screen.dart';
import 'package:journal/screens/journals_screen.dart';
import 'package:journal/screens/bin_screen.dart';
import 'package:journal/theme/app_theme.dart';
import 'package:journal/widgets/year_grid.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final screen in <String, Widget>{
      'feed': const FeedScreen(),
      'calendar': const CalendarScreen(),
      'stats': const StatsScreen(),
      'settings': const SettingsScreen(),
      'journals': const JournalsScreen(),
      'bin': const BinScreen(),
      'year': const Scaffold(body: YearGrid()),
    }.entries) {
      testWidgets('${screen.key} renders at 320dp, 2x text, $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase.withExecutor(NativeDatabase.memory());
        final id = (await db.select(db.journals).get()).first.id;
        await db.insertEntry(
          EntriesCompanion.insert(
            journalId: id,
            contentJson: '[{"insert":"A little writing\\n"}]',
            plainText: const Value('A little writing'),
            title: const Value('A day to remember'),
            entryDate: DateTime.now(),
            mood: const Value(4),
            writingSeconds: const Value(600),
            wordCount: const Value(3),
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              theme: buildTheme(brightness: brightness),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: screen.value,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final scrollables = find.byType(Scrollable);
        if (screen.key != 'calendar' && scrollables.evaluate().isNotEmpty) {
          await tester.drag(scrollables.first, const Offset(0, -1800));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
        await db.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
