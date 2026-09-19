import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';

void main() {
  group('day ends at', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('defaults to midnight', () async {
      expect(await db.watchDayEndsAt().first, 0);
    });

    test('a change is stored and re-emitted', () async {
      final seen = <int>[];
      final sub = db.watchDayEndsAt().listen(seen.add);
      await pumpEventQueue();
      await db.setDayEndsAt(3);
      await pumpEventQueue();
      await db.setDayEndsAt(5);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [0, 3, 5]);
      expect(await db.watchDayEndsAt().first, 5);
    });

    test('out-of-range hours are clamped', () async {
      await db.setDayEndsAt(30);
      expect(await db.watchDayEndsAt().first, AppDatabase.maxDayEndsAt);
      await db.setDayEndsAt(-2);
      expect(await db.watchDayEndsAt().first, 0);
    });
  });

  test('upgrading a v2 database adds the settings table and keeps entries',
      () async {
    final dir = await Directory.systemTemp.createTemp('journal_migration');
    final file = File('${dir.path}/journal.sqlite');
    try {
      // Build a v2 database: today's schema minus the settings table.
      final old = AppDatabase.withExecutor(NativeDatabase(file));
      final journalId = await old.createJournal('Old', 0, '📔');
      await old.insertEntry(EntriesCompanion.insert(
        journalId: journalId,
        contentJson: '[]',
        entryDate: DateTime(2026, 9, 3),
      ));
      await old.customStatement('DROP TABLE settings');
      await old.customStatement('PRAGMA user_version = 2');
      await old.close();

      final upgraded = AppDatabase.withExecutor(NativeDatabase(file));
      expect(await upgraded.watchDayEndsAt().first, 0);
      await upgraded.setDayEndsAt(2);
      expect(await upgraded.watchDayEndsAt().first, 2);
      expect(await upgraded.select(upgraded.entries).get(), hasLength(1));
      await upgraded.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
