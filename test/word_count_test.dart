import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';

/// The feed reads `entries.word_count`, the editor writes it, and the schema v2
/// migration repairs it. All three go through [countWords], so these cover the
/// one number the user actually sees on a card.
void main() {
  group('countWords', () {
    test('counts whitespace-separated runs', () {
      expect(countWords('one two three'), 3);
      expect(countWords('  padded   out  '), 2);
      expect(countWords('line\nbreaks\tand\r\ntabs'), 4);
    });

    test('empty and whitespace-only text is zero words', () {
      expect(countWords(''), 0);
      expect(countWords('   \n\t '), 0);
    });

    test('a single word is one word, not zero', () {
      expect(countWords('today'), 1);
    });
  });

  group('schema v2 repair', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('journal_wc_test');
      file = File('${dir.path}/journal.sqlite');
    });

    tearDown(() => dir.delete(recursive: true));

    test('word counts frozen by the old editor are recomputed on upgrade',
        () async {
      // Build a v1 database by hand: the schema is identical, only the stored
      // counts are wrong, which is exactly the state a device is left in after
      // writing an entry on top of a template.
      final v1 = AppDatabase.withExecutor(NativeDatabase(file));
      final journalId = await v1.createJournal('Test', 0xFF6750A4, '📔');
      final stale = await v1.insertEntry(EntriesCompanion.insert(
        journalId: journalId,
        contentJson: '[]',
        plainText: const Value('four words were written here'),
        entryDate: DateTime(2026, 9, 3),
        wordCount: const Value(0), // what the detached listener left behind
      ));
      final untouched = await v1.insertEntry(EntriesCompanion.insert(
        journalId: journalId,
        contentJson: '[]',
        plainText: const Value('two words'),
        entryDate: DateTime(2026, 9, 2),
        wordCount: const Value(2),
      ));
      await v1.customStatement('PRAGMA user_version = 1');
      await v1.close();

      final v2 = AppDatabase.withExecutor(NativeDatabase(file));
      addTearDown(v2.close);

      expect((await v2.getEntry(stale))!.wordCount, 5);
      expect((await v2.getEntry(untouched))!.wordCount, 2);
    });

    test('an entry with no text stays at zero', () async {
      final v1 = AppDatabase.withExecutor(NativeDatabase(file));
      final journalId = await v1.createJournal('Test', 0xFF6750A4, '📔');
      final empty = await v1.insertEntry(EntriesCompanion.insert(
        journalId: journalId,
        contentJson: '[]',
        entryDate: DateTime(2026, 9, 3),
        wordCount: const Value(7), // nonsense count, no text to back it
      ));
      await v1.customStatement('PRAGMA user_version = 1');
      await v1.close();

      final v2 = AppDatabase.withExecutor(NativeDatabase(file));
      addTearDown(v2.close);
      expect((await v2.getEntry(empty))!.wordCount, 0);
    });
  });
}
