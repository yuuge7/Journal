import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';
import 'package:journal/providers.dart';
import 'package:journal/theme/app_theme.dart';
import 'package:journal/widgets/entry_link_sheet.dart';

void main() {
  testWidgets('entry links search beyond the first page and respect the bin', (
    tester,
  ) async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    final journal = (await db.select(db.journals).get()).first.id;
    final old = await db.insertEntry(
      EntriesCompanion.insert(
        journalId: journal,
        title: const Value('Distant memory'),
        contentJson: '[]',
        entryDate: DateTime(2020),
      ),
    );
    for (var i = 0; i < 110; i++) {
      await db.insertEntry(
        EntriesCompanion.insert(
          journalId: journal,
          title: Value('Recent page $i'),
          contentJson: '[]',
          entryDate: DateTime(2026, 1, i + 1),
        ),
      );
    }
    Entry? selected;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildTheme(brightness: Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showEntryLinkSheet(context);
                },
                child: const Text('Link entry'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Link entry'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Distant memory'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Distant');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Distant memory'), findsOneWidget);
    await tester.tap(find.text('Distant memory'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(selected?.id, old);
    final stableId = (await db.getEntry(old))!.stableId;
    expect((await db.getEntryByStableId(stableId))!.id, old);
    await db.deleteEntry(old);
    expect(await db.getEntryByStableId(stableId), isNull);
    await db.restoreEntry(old);
    await db.deleteJournal(journal);
    expect(await db.getEntryByStableId(stableId), isNull);
    await db.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
