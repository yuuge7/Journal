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
// Day math
// ---------------------------------------------------------------------------
//
// drift stores DateTimes as unix seconds and returns them as *local* times,
// while SQLite's strftime(…, 'unixepoch') formats in UTC. Bucketing entries
// into days inside SQL therefore pushes anything written near midnight into
// the neighbouring day (an entry dated the 22nd at 01:30 in UTC+3 is grouped
// under the 21st). All day bucketing happens in Dart instead; SQL only gets
// range filters whose bounds are local midnights.

/// Words in [text], counted the same way everywhere: whitespace-separated
/// runs of a trimmed string. The editor, the feed card and the v2 migration
/// all go through here so a count can never disagree with itself.
int countWords(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

/// Local calendar day (midnight) that [dt] falls on.
DateTime localDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Number of the calendar day [dt] falls on, counted from the epoch.
///
/// Use differences of this instead of `Duration.inDays` between two days: a
/// calendar day is 23 or 25 hours long around a DST switch, which makes
/// `inDays` report 0 for two genuinely consecutive days.
int dayOrdinal(DateTime dt) =>
    DateTime.utc(dt.year, dt.month, dt.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;

/// Current and longest run of consecutive days that have at least one entry.
///
/// Days after [now] (entries dated into the future) never start or extend the
/// current streak; the current streak is only alive if the newest past day is
/// today or yesterday.
StreakInfo computeStreaks(Iterable<DateTime> entryDates, {DateTime? now}) {
  final today = dayOrdinal(now ?? DateTime.now());
  final days = <int>{for (final d in entryDates) dayOrdinal(d)}.toList()..sort();
  if (days.isEmpty) return const StreakInfo(current: 0, longest: 0);

  var longest = 1, run = 1;
  for (var i = 1; i < days.length; i++) {
    run = days[i] - days[i - 1] == 1 ? run + 1 : 1;
    if (run > longest) longest = run;
  }

  final past = days.where((d) => d <= today).toList();
  if (past.isEmpty || today - past.last > 1) {
    return StreakInfo(current: 0, longest: longest);
  }
  var current = 1;
  for (var i = past.length - 1; i > 0; i--) {
    if (past[i] - past[i - 1] != 1) break;
    current++;
  }
  return StreakInfo(current: current, longest: longest);
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
  int get schemaVersion => 2;

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
        onUpgrade: (m, from, to) async {
          if (from < 2) await _repairWordCounts();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Recomputes every stored word count from the plain-text mirror.
  ///
  /// Before v2 the editor read its count off a listener bound to the Quill
  /// document it was created with. Loading a template swapped that document
  /// out, so the listener stopped firing and the count froze at the template's
  /// own length — zero for the "Blank" template, which is what the feed then
  /// showed however much was written. `plainText` was always written from the
  /// live document, so it is the trustworthy side of the pair.
  Future<void> _repairWordCounts() async {
    final rows = await select(entries).get();
    final stale = [
      for (final e in rows)
        if (countWords(e.plainText) != e.wordCount) e
    ];
    if (stale.isEmpty) return;
    await batch((b) {
      for (final e in stale) {
        b.update(
          entries,
          EntriesCompanion(wordCount: Value(countWords(e.plainText))),
          where: (t) => t.id.equals(e.id),
        );
      }
    });
  }

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

  /// How many years back "on this day" looks. Well past a lifetime of
  /// journaling, and the date picker cannot reach further than year 2000.
  static const _throwbackYears = 60;

  /// Entries from previous years whose entryDate falls on the same day + month
  /// as [today].
  ///
  /// Matching is a union of local-midnight day ranges, one per past year, so
  /// the comparison stays in local time and DST cannot shift a day.
  Stream<List<Entry>> watchThrowback(DateTime today) {
    Expression<bool>? sameDay;
    for (var year = today.year - 1;
        year >= today.year - _throwbackYears;
        year--) {
      final start = DateTime(year, today.month, today.day);
      // Feb 29 rolls into Mar 1 in a common year — that year has no such day.
      if (start.month != today.month) continue;
      final end = DateTime(year, today.month, today.day + 1);
      final range = entries.entryDate.isBiggerOrEqualValue(start) &
          entries.entryDate.isSmallerThanValue(end);
      sameDay = sameDay == null ? range : sameDay | range;
    }
    if (sameDay == null) return Stream.value(const []);

    return (select(entries)
          ..where((e) => e.isDraft.equals(false) & sameDay!)
          ..orderBy([(e) => OrderingTerm.desc(e.entryDate)]))
        .watch();
  }

  // -------------------------------------------------------------------------
  // Calendar
  // -------------------------------------------------------------------------

  /// Entry counts per day for the given month, for calendar markers.
  /// Keys are local midnights, matching what the calendar grid asks for.
  Stream<Map<DateTime, int>> watchMonthCounts(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 1);
    return _watchEntryDates((e) =>
            e.entryDate.isBiggerOrEqualValue(first) &
            e.entryDate.isSmallerThanValue(last))
        .map((dates) {
      final map = <DateTime, int>{};
      for (final date in dates) {
        map.update(localDay(date), (c) => c + 1, ifAbsent: () => 1);
      }
      return map;
    });
  }

  /// The entries shown when a calendar day is tapped — the same set the dot
  /// markers count, so a day never shows entries without a dot.
  Stream<List<Entry>> watchEntriesOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return (select(entries)
          ..where((e) =>
              e.isDraft.equals(false) &
              e.entryDate.isBiggerOrEqualValue(start) &
              e.entryDate.isSmallerThanValue(end))
          ..orderBy([(e) => OrderingTerm.desc(e.entryDate)]))
        .watch();
  }

  // -------------------------------------------------------------------------
  // Statistics
  // -------------------------------------------------------------------------

  /// entryDates of every non-draft entry, optionally narrowed by [filter].
  /// Only the date column is read, so bucketing in Dart stays cheap.
  Stream<List<DateTime>> _watchEntryDates(
      [Expression<bool> Function($EntriesTable e)? filter]) {
    final q = selectOnly(entries)..addColumns([entries.entryDate]);
    q.where(entries.isDraft.equals(false) &
        (filter == null ? const Constant(true) : filter(entries)));
    return q.watch().map(
        (rows) => [for (final r in rows) r.read(entries.entryDate)!]);
  }

  /// Streaks = consecutive calendar days with at least one entry.
  Stream<StreakInfo> watchStreaks() =>
      _watchEntryDates().map((dates) => computeStreaks(dates));

  Stream<GlobalStats> watchGlobalStats() {
    return customSelect(
      "SELECT "
      "(SELECT COUNT(*) FROM entries WHERE is_draft = 0) AS total_entries, "
      "(SELECT COALESCE(SUM(word_count), 0) FROM entries WHERE is_draft = 0) AS total_words, "
      "(SELECT COALESCE(SUM(writing_seconds), 0) FROM entries WHERE is_draft = 0) AS total_seconds, "
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

  /// Entries per day over the 30 days ending today, oldest first. Entries
  /// dated in the future are left out — the chart only draws these 30 days.
  Stream<List<DayCount>> watchLast30DaysActivity() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 29);
    final end = DateTime(now.year, now.month, now.day + 1);
    return _watchEntryDates((e) =>
            e.entryDate.isBiggerOrEqualValue(start) &
            e.entryDate.isSmallerThanValue(end))
        .map((dates) {
      final counts = <DateTime, int>{};
      for (final date in dates) {
        counts.update(localDay(date), (c) => c + 1, ifAbsent: () => 1);
      }
      final days = counts.keys.toList()..sort();
      return [for (final day in days) DayCount(day, counts[day]!)];
    });
  }
}
