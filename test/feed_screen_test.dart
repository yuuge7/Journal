import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';
import 'package:journal/providers.dart';
import 'package:journal/screens/feed_screen.dart';
import 'package:journal/theme/app_theme.dart';

/// The feed is the screen the app lives on, and the way it breaks is silent: a
/// layout assertion inside a sliver throws during `performLayout`, the whole
/// scroll view renders nothing, and the chrome around it still looks correct.
/// A blank feed with entries in the database therefore gets a test of its own.
///
/// The database is opened and closed inside the test body rather than in
/// `setUp`/`tearDown`. `testWidgets` runs its body in a fake-async zone; a
/// database opened outside that zone never finishes closing inside it, and the
/// run hangs with no useful message.
void main() {
  testWidgets('entries reach the screen, grouped under their day', (tester) async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    await _seed(db, {0: ['Slow start', 'Ran the long loop'], 1: ['The review went fine']});
    await _pumpFeed(tester, db);

    expect(find.text('Slow start'), findsOneWidget);
    expect(find.text('Ran the long loop'), findsOneWidget);
    expect(find.text('The review went fine'), findsOneWidget);
    // Today is named rather than dated, and the heading is stated once even
    // though two entries hang off it.
    expect(find.text('TODAY'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await db.close();
  });

  testWidgets('a run of days with nothing in it is drawn, not closed up',
      (tester) async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    await _seed(db, {0: ['Today'], 4: ['Four days ago']});
    await _pumpFeed(tester, db);

    expect(find.text('NOTHING FOR 3 DAYS'), findsOneWidget);

    await db.close();
  });

  testWidgets('an empty journal says what to do next', (tester) async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    await db.createJournal('Personal', 0xFF7A6BB5, '📔');
    await _pumpFeed(tester, db);

    expect(find.text('Nothing written yet'), findsOneWidget);
    expect(find.text('Write today'), findsOneWidget);

    await db.close();
  });
}

/// `{days ago: [titles]}`.
Future<void> _seed(AppDatabase db, Map<int, List<String>> plan) async {
  final journalId = await db.createJournal('Personal', 0xFF7A6BB5, '📔');
  for (final entry in plan.entries) {
    for (final title in entry.value) {
      await db.insertEntry(EntriesCompanion.insert(
        journalId: journalId,
        title: Value(title),
        contentJson: '[]',
        plainText: Value('$title — the opening of the writing.'),
        entryDate: DateTime.now().subtract(Duration(days: entry.key)),
        wordCount: const Value(9),
        writingSeconds: const Value(600),
        mood: const Value(4),
      ));
    }
  }
}

Future<void> _pumpFeed(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: MaterialApp(
      theme: buildTheme(brightness: Brightness.light),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: const FeedScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
