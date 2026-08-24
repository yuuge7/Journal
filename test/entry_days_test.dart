import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';

/// Day-based queries run against a real in-memory SQLite database, because the
/// bug these cover only shows up in the SQL/Dart boundary: drift stores unix
/// seconds, and formatting those in SQL happens in UTC.
void main() {
  late AppDatabase db;
  late int journalId;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    journalId = await db.createJournal('Test', 0xFF6750A4, '📔');
  });

  tearDown(() => db.close());

  Future<int> addEntry(DateTime entryDate,
          {bool draft = false, int words = 10}) =>
      db.insertEntry(EntriesCompanion.insert(
        journalId: journalId,
        contentJson: '[]',
        entryDate: entryDate,
        wordCount: Value(words),
        isDraft: Value(draft),
      ));

  group('calendar', () {
    test('an entry lands on the day it is dated, whatever the time of day',
        () async {
      for (final hour in [0, 1, 2, 12, 21, 23]) {
        final db2 = AppDatabase.withExecutor(NativeDatabase.memory());
        final j = await db2.createJournal('T', 0, '📔');
        await db2.insertEntry(EntriesCompanion.insert(
          journalId: j,
          contentJson: '[]',
          entryDate: DateTime(2026, 8, 22, hour, 30),
        ));
        final counts = await db2.watchMonthCounts(DateTime(2026, 8)).first;
        expect(counts, {DateTime(2026, 8, 22): 1},
            reason: 'entry written at $hour:30 was bucketed on the wrong day');
        await db2.close();
      }
    });

    test('counts add up per day and ignore other months', () async {
      await addEntry(DateTime(2026, 8, 22, 1, 30));
      await addEntry(DateTime(2026, 8, 22, 20, 0));
      await addEntry(DateTime(2026, 8, 23, 0, 5));
      await addEntry(DateTime(2026, 9, 1, 0, 30));
      await addEntry(DateTime(2026, 7, 31, 23, 30));

      final counts = await db.watchMonthCounts(DateTime(2026, 8)).first;
      expect(counts, {DateTime(2026, 8, 22): 2, DateTime(2026, 8, 23): 1});
    });

    test('drafts get no dot and are not listed under the day', () async {
      await addEntry(DateTime(2026, 8, 22, 1, 30), draft: true);
      expect(await db.watchMonthCounts(DateTime(2026, 8)).first, isEmpty);
      expect(await db.watchEntriesOn(DateTime(2026, 8, 22)).first, isEmpty);
    });

    test('the day list matches the dots', () async {
      await addEntry(DateTime(2026, 8, 22, 0, 30));
      await addEntry(DateTime(2026, 8, 22, 23, 45));
      await addEntry(DateTime(2026, 8, 23, 12, 0));

      final counts = await db.watchMonthCounts(DateTime(2026, 8)).first;
      for (final day in counts.keys) {
        final listed = await db.watchEntriesOn(day).first;
        expect(listed.length, counts[day]);
        for (final e in listed) {
          expect(localDay(e.entryDate), day);
        }
      }
      expect(await db.watchEntriesOn(DateTime(2026, 8, 21)).first, isEmpty);
    });

    test('re-dating an entry moves its dot', () async {
      final id = await addEntry(DateTime(2026, 8, 23, 16, 0));
      await db.updateEntry(
          id, EntriesCompanion(entryDate: Value(DateTime(2026, 8, 22, 16, 0))));

      final counts = await db.watchMonthCounts(DateTime(2026, 8)).first;
      expect(counts, {DateTime(2026, 8, 22): 1});
    });
  });

  group('throwback', () {
    test('matches the same day in earlier years only', () async {
      await addEntry(DateTime(2025, 8, 24, 0, 30)); // same day, last year
      await addEntry(DateTime(2020, 8, 24, 23, 30)); // same day, 6 years back
      await addEntry(DateTime(2025, 8, 23, 12, 0)); // neighbouring day
      await addEntry(DateTime(2026, 8, 24, 9, 0)); // today, not a throwback
      await addEntry(DateTime(2025, 8, 24, 12, 0), draft: true);

      final memories = await db.watchThrowback(DateTime(2026, 8, 24, 15)).first;
      expect(memories.map((e) => e.entryDate.year), [2025, 2020]);
    });

    test('no memories yet', () async {
      await addEntry(DateTime(2026, 8, 24, 9, 0));
      expect(await db.watchThrowback(DateTime(2026, 8, 24, 15)).first, isEmpty);
    });
  });

  group('streaks over the database', () {
    test('drafts do not extend a streak, finished entries do', () async {
      final now = DateTime.now();
      await addEntry(now.subtract(const Duration(days: 1)), draft: true);
      await addEntry(now);

      expect((await db.watchStreaks().first).current, 1);

      // Finishing the draft joins the two days up.
      await (db.update(db.entries)..where((e) => e.isDraft.equals(true)))
          .write(const EntriesCompanion(isDraft: Value(false)));
      expect((await db.watchStreaks().first).current, 2);
    });

    test('a midnight entry counts for its own day', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await addEntry(today.add(const Duration(minutes: 30)));
      expect((await db.watchStreaks().first).current, 1);
    });
  });

  group('activity chart', () {
    test('buckets by local day and skips future entries', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await addEntry(today.add(const Duration(minutes: 15)));
      await addEntry(DateTime(today.year, today.month, today.day - 2, 3, 0));
      await addEntry(today.subtract(const Duration(days: 45)));
      await addEntry(today.add(const Duration(days: 3)));

      final activity = await db.watchLast30DaysActivity().first;
      expect(activity.map((d) => d.day),
          [DateTime(today.year, today.month, today.day - 2), today]);
      expect(activity.every((d) => d.count == 1), isTrue);
    });
  });
}
