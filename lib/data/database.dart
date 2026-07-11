import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

/// A journal is a category / notebook. 1-to-N with entries.
class Journals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 64)();
  IntColumn get color => integer()(); // ARGB value of the accent color
  TextColumn get emoji => text().withDefault(const Constant('📔'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Entries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get journalId =>
      integer().references(Journals, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withDefault(const Constant(''))();

  /// Quill delta document encoded as JSON.
  TextColumn get contentJson => text()();

  /// Plain-text rendering of the document, used for search + word count.
  TextColumn get plainText => text().withDefault(const Constant(''))();

  /// The day this entry belongs to (used for calendar, throwback, streaks).
  DateTimeColumn get entryDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get wordCount => integer().withDefault(const Constant(0))();

  /// Accumulated seconds spent writing this entry.
  IntColumn get writingSeconds => integer().withDefault(const Constant(0))();

  /// Mood 1 (bad) .. 5 (great), optional.
  IntColumn get mood => integer().nullable()();

  BoolColumn get isDraft => boolean().withDefault(const Constant(false))();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique().withLength(min: 1, max: 32)();
}

/// M-to-N between entries and tags.
class EntryTags extends Table {
  IntColumn get entryId =>
      integer().references(Entries, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {entryId, tagId};
}

/// Image attachments. The file itself lives in the app documents directory
/// under `attachments/`; [fileName] is relative to that folder.
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId =>
      integer().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ---------------------------------------------------------------------------
// Result helpers
// ---------------------------------------------------------------------------

class DayCount {
  final DateTime day;
  final int count;
  const DayCount(this.day, this.count);
}

class StreakInfo {
  final int current;
  final int longest;
  const StreakInfo({required this.current, required this.longest});
}

class GlobalStats {
  final int totalEntries;
  final int totalWords;
  final int totalWritingSeconds;
  final int totalAttachments;
  final double avgWordsPerEntry;
  const GlobalStats({
    required this.totalEntries,
    required this.totalWords,
    required this.totalWritingSeconds,
    required this.totalAttachments,
    required this.avgWordsPerEntry,
  });
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Journals, Entries, Tags, EntryTags, Attachments])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'journal'));

  /// For tests / import tooling.
  AppDatabase.withExecutor(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Seed a default journal so the editor always has a target.
          await into(journals).insert(JournalsCompanion.insert(
            name: 'Personal',
            color: 0xFF6750A4,
            emoji: const Value('📔'),
          ));
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // -------------------------------------------------------------------------
  // Journals
  // -------------------------------------------------------------------------

  Stream<List<Journal>> watchJournals() =>
      (select(journals)..orderBy([(j) => OrderingTerm.asc(j.createdAt)]))
          .watch();

  Future<int> createJournal(String name, int color, String emoji) =>
      into(journals).insert(JournalsCompanion.insert(
          name: name, color: color, emoji: Value(emoji)));

  Future<void> renameJournal(int id, String name, int color, String emoji) =>
      (update(journals)..where((j) => j.id.equals(id))).write(
          JournalsCompanion(
              name: Value(name), color: Value(color), emoji: Value(emoji)));

  Future<void> deleteJournal(int id) =>
      (delete(journals)..where((j) => j.id.equals(id))).go();

  // -------------------------------------------------------------------------
  // Entries
  // -------------------------------------------------------------------------

  /// Chronological feed, newest first. Optional journal filter and full-text
  /// search over title + plain text.
  Stream<List<Entry>> watchFeed({int? journalId, String? search}) {
    final q = select(entries)
      ..orderBy([(e) => OrderingTerm.desc(e.entryDate)]);
    if (journalId != null) {
      q.where((e) => e.journalId.equals(journalId));
    }
    if (search != null && search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      q.where((e) => e.title.like(like) | e.plainText.like(like));
    }
    return q.watch();
  }

  Future<Entry?> getEntry(int id) =>
      (select(entries)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<int> insertEntry(EntriesCompanion companion) =>
      into(entries).insert(companion);

  Future<void> updateEntry(int id, EntriesCompanion companion) =>
      (update(entries)..where((e) => e.id.equals(id))).write(companion);

  Future<void> deleteEntry(int id) =>
      (delete(entries)..where((e) => e.id.equals(id))).go();

  // -------------------------------------------------------------------------
  // Tags
  // -------------------------------------------------------------------------

  Stream<List<Tag>> watchTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  /// Map of entryId -> tags, kept as one stream so the feed needs a single
  /// subscription instead of one per card.
  Stream<Map<int, List<Tag>>> watchTagsByEntry() {
    final query = select(entryTags).join(
        [innerJoin(tags, tags.id.equalsExp(entryTags.tagId))]);
    return query.watch().map((rows) {
      final map = <int, List<Tag>>{};
      for (final row in rows) {
        final link = row.readTable(entryTags);
        final tag = row.readTable(tags);
        map.putIfAbsent(link.entryId, () => []).add(tag);
      }
      return map;
    });
  }

  Future<int> ensureTag(String name) async {
    final existing = await (select(tags)
          ..where((t) => t.name.equals(name.trim())))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    return into(tags).insert(TagsCompanion.insert(name: name.trim()));
  }

  Future<void> setEntryTags(int entryId, List<int> tagIds) => transaction(() async {
        await (delete(entryTags)..where((et) => et.entryId.equals(entryId))).go();
        for (final tagId in tagIds) {
          await into(entryTags)
              .insert(EntryTagsCompanion.insert(entryId: entryId, tagId: tagId));
        }
      });

  Future<List<Tag>> tagsForEntry(int entryId) async {
    final query = select(entryTags).join(
        [innerJoin(tags, tags.id.equalsExp(entryTags.tagId))])
      ..where(entryTags.entryId.equals(entryId));
    final rows = await query.get();
    return rows.map((r) => r.readTable(tags)).toList();
  }

  Future<void> deleteTag(int id) =>
      (delete(tags)..where((t) => t.id.equals(id))).go();

  // -------------------------------------------------------------------------
  // Attachments
  // -------------------------------------------------------------------------

  Stream<List<Attachment>> watchAttachments(int entryId) =>
      (select(attachments)..where((a) => a.entryId.equals(entryId))).watch();

  Future<List<Attachment>> attachmentsForEntry(int entryId) =>
      (select(attachments)..where((a) => a.entryId.equals(entryId))).get();

  /// entryId -> first attachment file name; used for feed thumbnails.
  Stream<Map<int, String>> watchThumbnails() {
    return select(attachments).watch().map((rows) {
      final map = <int, String>{};
      for (final a in rows) {
        map.putIfAbsent(a.entryId, () => a.fileName);
      }
      return map;
    });
  }

  Future<int> addAttachment(int entryId, String fileName) => into(attachments)
      .insert(AttachmentsCompanion.insert(entryId: entryId, fileName: fileName));

  Future<void> removeAttachment(int id) =>
      (delete(attachments)..where((a) => a.id.equals(id))).go();

  // -------------------------------------------------------------------------
  // Throwback / "On this day"
  // -------------------------------------------------------------------------

  /// Entries from previous years whose entryDate has the same day + month as
  /// [today]. Drift stores DateTimes as unix seconds, hence 'unixepoch'.
  Stream<List<Entry>> watchThrowback(DateTime today) {
    final mmdd =
        "${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    return customSelect(
      "SELECT * FROM entries "
      "WHERE strftime('%m-%d', entry_date, 'unixepoch') = ?1 "
      "AND CAST(strftime('%Y', entry_date, 'unixepoch') AS INTEGER) < ?2 "
      "AND is_draft = 0 "
      "ORDER BY entry_date DESC",
      variables: [
        Variable.withString(mmdd),
        Variable.withInt(today.year),
      ],
      readsFrom: {entries},
    ).watch().map((rows) =>
        [for (final row in rows) entries.map(row.data)]);
  }

  // -------------------------------------------------------------------------
  // Calendar
  // -------------------------------------------------------------------------

  /// Entry counts per day for the given month, for calendar markers.
  Stream<Map<DateTime, int>> watchMonthCounts(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 1);
    return customSelect(
      "SELECT strftime('%Y-%m-%d', entry_date, 'unixepoch') AS day, "
      "COUNT(*) AS c FROM entries "
      "WHERE entry_date >= ?1 AND entry_date < ?2 AND is_draft = 0 "
      "GROUP BY day",
      variables: [
        Variable.withInt(first.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(last.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {entries},
    ).watch().map((rows) {
      final map = <DateTime, int>{};
      for (final row in rows) {
        final parts = row.read<String>('day').split('-');
        map[DateTime(
                int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))] =
            row.read<int>('c');
      }
      return map;
    });
  }

  Stream<List<Entry>> watchEntriesOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(entries)
          ..where((e) =>
              e.entryDate.isBiggerOrEqualValue(start) &
              e.entryDate.isSmallerThanValue(end))
          ..orderBy([(e) => OrderingTerm.desc(e.entryDate)]))
        .watch();
  }

  // -------------------------------------------------------------------------
  // Statistics
  // -------------------------------------------------------------------------

  /// Distinct writing days, newest first, as 'yyyy-MM-dd' strings.
  Stream<List<String>> _watchDistinctDays() {
    return customSelect(
      "SELECT DISTINCT strftime('%Y-%m-%d', entry_date, 'unixepoch') AS day "
      "FROM entries WHERE is_draft = 0 ORDER BY day DESC",
      readsFrom: {entries},
    ).watch().map((rows) => [for (final r in rows) r.read<String>('day')]);
  }

  /// Streaks = consecutive calendar days with at least one entry.
  Stream<StreakInfo> watchStreaks() {
    return _watchDistinctDays().map((dayStrings) {
      if (dayStrings.isEmpty) {
        return const StreakInfo(current: 0, longest: 0);
      }
      final days = dayStrings.map(DateTime.parse).toList(); // newest first

      // Longest run anywhere in history.
      var longest = 1, run = 1;
      for (var i = 1; i < days.length; i++) {
        if (days[i - 1].difference(days[i]).inDays == 1) {
          run++;
          if (run > longest) longest = run;
        } else {
          run = 1;
        }
      }

      // Current streak: counts if the last write was today or yesterday.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      var current = 0;
      if (today.difference(days.first).inDays <= 1) {
        current = 1;
        for (var i = 1; i < days.length; i++) {
          if (days[i - 1].difference(days[i]).inDays == 1) {
            current++;
          } else {
            break;
          }
        }
      }
      return StreakInfo(current: current, longest: longest);
    });
  }

  Stream<GlobalStats> watchGlobalStats() {
    return customSelect(
      "SELECT "
      "(SELECT COUNT(*) FROM entries WHERE is_draft = 0) AS total_entries, "
      "(SELECT COALESCE(SUM(word_count), 0) FROM entries WHERE is_draft = 0) AS total_words, "
      "(SELECT COALESCE(SUM(writing_seconds), 0) FROM entries) AS total_seconds, "
      "(SELECT COUNT(*) FROM attachments) AS total_attachments",
      readsFrom: {entries, attachments},
    ).watchSingle().map((row) {
      final totalEntries = row.read<int>('total_entries');
      final totalWords = row.read<int>('total_words');
      return GlobalStats(
        totalEntries: totalEntries,
        totalWords: totalWords,
        totalWritingSeconds: row.read<int>('total_seconds'),
        totalAttachments: row.read<int>('total_attachments'),
        avgWordsPerEntry:
            totalEntries == 0 ? 0 : totalWords / totalEntries,
      );
    });
  }

  /// Entries per journal, for the stats screen.
  Stream<List<DayCount>> watchLast30DaysActivity() {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return customSelect(
      "SELECT strftime('%Y-%m-%d', entry_date, 'unixepoch') AS day, "
      "COUNT(*) AS c FROM entries "
      "WHERE entry_date >= ?1 AND is_draft = 0 GROUP BY day ORDER BY day",
      variables: [Variable.withInt(cutoff.millisecondsSinceEpoch ~/ 1000)],
      readsFrom: {entries},
    ).watch().map((rows) => [
          for (final r in rows)
            DayCount(DateTime.parse(r.read<String>('day')), r.read<int>('c'))
        ]);
  }
}
