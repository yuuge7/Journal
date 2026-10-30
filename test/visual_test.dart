@Tags(['golden'])
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart' show AppDatabase, EntriesCompanion;
import 'package:journal/providers.dart';
import 'package:journal/theme/app_theme.dart';
import 'package:journal/widgets/entry_row.dart';
import 'package:journal/widgets/time_spine.dart';

void main() {
  setUpAll(() async {
    for (final font in ['SchibstedGrotesk-Regular', 'Literata-Regular']) {
      await (FontLoader(
        font.startsWith('Literata') ? 'Literata' : 'Schibsted Grotesk',
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  for (final brightness in Brightness.values) {
    testWidgets('entry and weighted spine golden $brightness', (tester) async {
      final db = AppDatabase.withExecutor(NativeDatabase.memory());
      final journal = (await db.select(db.journals).get()).first.id;
      final id = await db.insertEntry(
        EntriesCompanion.insert(
          journalId: journal,
          contentJson: '[]',
          entryDate: DateTime(2026, 10, 30),
          // Keep the backfill label independent of the day the test runs.
          createdAt: Value(DateTime(2026, 10, 30, 15)),
          updatedAt: Value(DateTime(2026, 10, 30, 15)),
          title: const Value('A quiet afternoon'),
          plainText: const Value(
            'The light stayed a little longer today. I took the long way home.',
          ),
          wordCount: const Value(14),
          writingSeconds: const Value(600),
          mood: const Value(4),
        ),
      );
      final entry = (await db.getEntry(id))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: buildTheme(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.noScaling),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: const ValueKey('golden'),
                  child: SizedBox(
                    width: 320,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SpineRail(
                          node: SpineNode.today,
                          weight: .65,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('TODAY · 10 MIN'),
                          ),
                        ),
                        SpineRail(weight: .65, child: EntryRow(entry: entry)),
                        const SpineRail(
                          dotted: true,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('NOTHING FOR 3 DAYS'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byKey(const ValueKey('golden')),
        matchesGoldenFile('goldens/entry_spine_${brightness.name}.png'),
      );
      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
