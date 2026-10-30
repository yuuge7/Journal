import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

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
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
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
  TextColumn get stableId => text().withDefault(const Constant(''))();
  TextColumn get monthDay => text().withDefault(const Constant(''))();
  TextColumn get location => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
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

/// App preferences as key/value pairs. Kept in the database rather than a
/// separate preferences plugin so a setting is one more reactive stream like
/// everything else. Device-local: backups do not carry it.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
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
  final days = <int>{for (final d in entryDates) dayOrdinal(d)}.toList()
    ..sort();
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

/// Analytics never materialize the prose or rich-text documents.
class EntryInsight {
  const EntryInsight({
    required this.id,
    required this.journalId,
    required this.title,
    required this.entryDate,
    required this.createdAt,
    required this.updatedAt,
    required this.wordCount,
    required this.writingSeconds,
    required this.mood,
  });
  final int id, journalId, wordCount, writingSeconds;
  final String title;
  final DateTime entryDate, createdAt, updatedAt;
  final int? mood;
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [Journals, Entries, Tags, EntryTags, Attachments, Settings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'journal'));

  /// For tests / import tooling.
  AppDatabase.withExecutor(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSearch();
      // Seed a default journal so the editor always has a target.
      await into(journals).insert(
        JournalsCompanion.insert(
          name: 'Personal',
          color: 0xFF7A6BB5,
          emoji: const Value('📔'),
        ),
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await _repairWordCounts();
      if (from < 3) {
        await customStatement(
          'CREATE TABLE IF NOT EXISTS settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
        );
      }
      if (from < 4) {
        final journalColumns = (await customSelect(
          'PRAGMA table_info(journals)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        final entryColumns = (await customSelect(
          'PRAGMA table_info(entries)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        for (final column in [
          journals.archived,
          journals.sortOrder,
          journals.deletedAt,
        ]) {
          if (!journalColumns.contains(column.$name)) {
            await m.addColumn(journals, column);
          }
        }
        for (final column in [
          entries.stableId,
          entries.monthDay,
          entries.location,
          entries.deletedAt,
        ]) {
          if (!entryColumns.contains(column.$name)) {
            await m.addColumn(entries, column);
          }
        }
        for (final e in await select(entries).get()) {
          await (update(entries)..where((t) => t.id.equals(e.id))).write(
            EntriesCompanion(
              stableId: Value(
                e.stableId.isEmpty ? const Uuid().v4() : e.stableId,
              ),
              monthDay: Value(monthDayOf(e.entryDate)),
            ),
          );
        }
        await _createSearch();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static String monthDayOf(DateTime day) =>
      '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Future<void> _createSearch() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS entries_entry_date ON entries(entry_date)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS entries_stable_id ON entries(stable_id) WHERE stable_id != \'\'',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS entries_month_day ON entries(month_day)',
    );
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS entry_search USING fts5(title, plain_text, content=entries, content_rowid=id, tokenize="unicode61 remove_diacritics 2")',
    );
    await customStatement(
      "CREATE TRIGGER IF NOT EXISTS entries_fts_insert AFTER INSERT ON entries BEGIN INSERT INTO entry_search(rowid,title,plain_text) VALUES(new.id,new.title,new.plain_text); END",
    );
    await customStatement(
      "CREATE TRIGGER IF NOT EXISTS entries_fts_delete AFTER DELETE ON entries BEGIN INSERT INTO entry_search(entry_search,rowid,title,plain_text) VALUES('delete',old.id,old.title,old.plain_text); END",
    );
    await customStatement(
      "CREATE TRIGGER IF NOT EXISTS entries_fts_update AFTER UPDATE ON entries BEGIN INSERT INTO entry_search(entry_search,rowid,title,plain_text) VALUES('delete',old.id,old.title,old.plain_text); INSERT INTO entry_search(rowid,title,plain_text) VALUES(new.id,new.title,new.plain_text); END",
    );
    await customStatement(
      "INSERT INTO entry_search(entry_search) VALUES('rebuild')",
    );
  }

  Expression<bool> _visible($EntriesTable e) =>
      e.deletedAt.isNull() &
      e.journalId.isInQuery(
        selectOnly(journals)
          ..addColumns([journals.id])
          ..where(journals.deletedAt.isNull()),
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
    final rows = await customSelect(
      'SELECT id, plain_text, word_count FROM entries',
    ).get();
    for (final row in rows) {
      final words = countWords(row.read<String>('plain_text'));
      if (words != row.read<int>('word_count')) {
        await customUpdate(
          'UPDATE entries SET word_count = ? WHERE id = ?',
          variables: [Variable(words), Variable(row.read<int>('id'))],
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Journals
  // -------------------------------------------------------------------------

  Stream<List<Journal>> watchJournals({bool includeArchived = false}) =>
      (select(journals)
            ..where(
              (j) =>
                  j.deletedAt.isNull() &
                  (includeArchived
                      ? const Constant(true)
                      : j.archived.equals(false)),
            )
            ..orderBy([
              (j) => OrderingTerm.asc(j.sortOrder),
              (j) => OrderingTerm.asc(j.createdAt),
            ]))
          .watch();

  Future<int> createJournal(String name, int color, String emoji) =>
      into(journals).insert(
        JournalsCompanion.insert(name: name, color: color, emoji: Value(emoji)),
      );

  Future<void> renameJournal(int id, String name, int color, String emoji) =>
      (update(journals)..where((j) => j.id.equals(id))).write(
        JournalsCompanion(
          name: Value(name),
          color: Value(color),
          emoji: Value(emoji),
        ),
      );

  Future<void> deleteJournal(int id) =>
      (update(journals)..where((j) => j.id.equals(id))).write(
        JournalsCompanion(deletedAt: Value(DateTime.now())),
      );
  Future<void> restoreJournal(int id) =>
      (update(journals)..where((j) => j.id.equals(id))).write(
        const JournalsCompanion(deletedAt: Value(null)),
      );
  Future<void> archiveJournal(int id, bool archived) =>
      (update(journals)..where((j) => j.id.equals(id))).write(
        JournalsCompanion(archived: Value(archived)),
      );
  Future<void> reorderJournals(List<int> ids) => batch((b) {
    for (var i = 0; i < ids.length; i++) {
      b.update(
        journals,
        JournalsCompanion(sortOrder: Value(i)),
        where: (j) => j.id.equals(ids[i]),
      );
    }
  });

  // -------------------------------------------------------------------------
  // Entries
  // -------------------------------------------------------------------------

  /// Chronological feed, newest first. Optional journal filter and full-text
  /// search over title + plain text.
  Stream<List<Entry>> watchFeed({
    int? journalId,
    String? search,
    bool titlesOnly = false,
    int? year,
    int limit = 200,
    DateTime? before,
  }) {
    final q = select(entries)
      ..where(_visible)
      ..orderBy([
        (e) => OrderingTerm.desc(e.entryDate),
        (e) => OrderingTerm.desc(e.id),
      ])
      ..limit(limit);
    if (before != null) {
      q.where((e) => e.entryDate.isSmallerOrEqualValue(before));
    }
    if (year != null) {
      q.where(
        (e) =>
            e.entryDate.isBiggerOrEqualValue(DateTime(year)) &
            e.entryDate.isSmallerThanValue(DateTime(year + 1)),
      );
    }
    if (journalId != null) {
      q.where((e) => e.journalId.equals(journalId));
    }
    if (search != null && search.trim().isNotEmpty) {
      final terms = RegExp(
        r'[\p{L}\p{N}_]+',
        unicode: true,
      ).allMatches(search).map((m) => '"${m[0]}"*').join(' AND ');
      if (terms.isNotEmpty) {
        final fts = titlesOnly ? 'title : ($terms)' : terms;
        final escapedFts = fts.replaceAll("'", "''");
        final tagTerm = search
            .trim()
            .replaceFirst(RegExp(r'^#'), '')
            .replaceAll("'", "''");
        q.where(
          (e) =>
              CustomExpression<bool>(
                "entries.id IN (SELECT rowid FROM entry_search WHERE entry_search MATCH '$escapedFts')",
                watchedTables: [entries],
              ) |
              (titlesOnly
                  ? const Constant(false)
                  : CustomExpression<bool>(
                      "entries.id IN (SELECT entry_id FROM entry_tags JOIN tags ON tags.id = entry_tags.tag_id WHERE tags.name LIKE '%$tagTerm%')",
                      watchedTables: [tags, entryTags],
                    )),
        );
      } else {
        q.where((e) => e.id.equals(-1));
      }
    }
    return q.watch();
  }

  Future<Entry?> getEntry(int id) =>
      (select(entries)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<Entry?> getEntryByStableId(String id) => (select(
    entries,
  )..where((e) => _visible(e) & e.stableId.equals(id))).getSingleOrNull();

  Stream<Entry?> watchLatestDraft() =>
      (select(entries)
            ..where((e) => _visible(e) & e.isDraft.equals(true))
            ..orderBy([(e) => OrderingTerm.desc(e.updatedAt)])
            ..limit(1))
          .watchSingleOrNull();

  Future<int> insertEntry(EntriesCompanion companion) => into(entries).insert(
    companion.copyWith(
      stableId:
          companion.stableId.present && companion.stableId.value.isNotEmpty
          ? companion.stableId
          : Value(const Uuid().v4()),
      monthDay: companion.entryDate.present
          ? Value(monthDayOf(companion.entryDate.value))
          : companion.monthDay,
    ),
  );

  Future<void> updateEntry(int id, EntriesCompanion companion) =>
      (update(entries)..where((e) => e.id.equals(id))).write(
        companion.entryDate.present
            ? companion.copyWith(
                monthDay: Value(monthDayOf(companion.entryDate.value)),
              )
            : companion,
      );

  Future<void> deleteEntry(int id) =>
      (update(entries)..where((e) => e.id.equals(id))).write(
        EntriesCompanion(deletedAt: Value(DateTime.now())),
      );
  Future<void> restoreEntry(int id) =>
      (update(entries)..where((e) => e.id.equals(id))).write(
        const EntriesCompanion(deletedAt: Value(null)),
      );
  Stream<List<Entry>> watchBin() =>
      (select(entries)
            ..where((e) => e.deletedAt.isNotNull())
            ..orderBy([(e) => OrderingTerm.desc(e.deletedAt)]))
          .watch();
  Stream<List<Journal>> watchDeletedJournals() =>
      (select(journals)..where((j) => j.deletedAt.isNotNull())).watch();
  Future<void> purgeBin({bool all = false}) => transaction(() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    await (delete(entries)..where(
          (e) =>
              e.deletedAt.isNotNull() &
              (all
                  ? const Constant(true)
                  : e.deletedAt.isSmallerThanValue(cutoff)),
        ))
        .go();
    await (delete(journals)..where(
          (j) =>
              j.deletedAt.isNotNull() &
              (all
                  ? const Constant(true)
                  : j.deletedAt.isSmallerThanValue(cutoff)),
        ))
        .go();
  });
  Future<void> bulkMove(Set<int> ids, int journalId) =>
      (update(entries)..where((e) => e.id.isIn(ids))).write(
        EntriesCompanion(journalId: Value(journalId)),
      );
  Future<void> bulkTag(Set<int> ids, String name) => transaction(() async {
    final tag = await ensureTag(name);
    for (final id in ids) {
      await into(entryTags).insert(
        EntryTagsCompanion.insert(entryId: id, tagId: tag),
        mode: InsertMode.insertOrIgnore,
      );
    }
  });

  Stream<List<EntryInsight>> watchInsights() {
    final q = selectOnly(entries)
      ..addColumns([
        entries.id,
        entries.journalId,
        entries.title,
        entries.entryDate,
        entries.createdAt,
        entries.updatedAt,
        entries.wordCount,
        entries.writingSeconds,
        entries.mood,
      ])
      ..where(_visible(entries) & entries.isDraft.equals(false))
      ..orderBy([OrderingTerm.asc(entries.entryDate)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          EntryInsight(
            id: r.read(entries.id)!,
            journalId: r.read(entries.journalId)!,
            title: r.read(entries.title)!,
            entryDate: r.read(entries.entryDate)!,
            createdAt: r.read(entries.createdAt)!,
            updatedAt: r.read(entries.updatedAt)!,
            wordCount: r.read(entries.wordCount)!,
            writingSeconds: r.read(entries.writingSeconds)!,
            mood: r.read(entries.mood),
          ),
      ],
    );
  }

  Stream<Map<DateTime, int>> watchHeat(int year) {
    final q = selectOnly(entries)
      ..addColumns([entries.entryDate, entries.writingSeconds])
      ..where(
        _visible(entries) &
            entries.isDraft.equals(false) &
            entries.entryDate.isBiggerOrEqualValue(DateTime(year)) &
            entries.entryDate.isSmallerThanValue(DateTime(year + 1)),
      );
    return q.watch().map((rows) {
      final result = <DateTime, int>{};
      for (final row in rows) {
        final day = localDay(row.read(entries.entryDate)!);
        final seconds = row.read(entries.writingSeconds)!;
        result.update(day, (s) => s + seconds, ifAbsent: () => seconds);
      }
      return result;
    });
  }

  Future<String?> setting(String key) async => (await (select(
    settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;
  Stream<String?> watchSetting(String key) => (select(
    settings,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((s) => s?.value);
  Future<void> setSetting(String key, String value) => into(
    settings,
  ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  // -------------------------------------------------------------------------
  // Tags
  // -------------------------------------------------------------------------

  Stream<List<Tag>> watchTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  /// Map of entryId -> tags, kept as one stream so the feed needs a single
  /// subscription instead of one per card.
  Stream<Map<int, List<Tag>>> watchTagsByEntry({List<int>? entryIds}) {
    final query = select(
      entryTags,
    ).join([innerJoin(tags, tags.id.equalsExp(entryTags.tagId))]);
    if (entryIds != null) query.where(entryTags.entryId.isIn(entryIds));
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
    final existing = await (select(
      tags,
    )..where((t) => t.name.equals(name.trim()))).getSingleOrNull();
    if (existing != null) return existing.id;
    return into(tags).insert(TagsCompanion.insert(name: name.trim()));
  }

  Future<void> setEntryTags(int entryId, List<int> tagIds) => transaction(
    () async {
      await (delete(entryTags)..where((et) => et.entryId.equals(entryId))).go();
      for (final tagId in tagIds) {
        await into(
          entryTags,
        ).insert(EntryTagsCompanion.insert(entryId: entryId, tagId: tagId));
      }
    },
  );

  Future<List<Tag>> tagsForEntry(int entryId) async {
    final query = select(entryTags).join([
      innerJoin(tags, tags.id.equalsExp(entryTags.tagId)),
    ])..where(entryTags.entryId.equals(entryId));
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
  Stream<Map<int, String>> watchThumbnails({List<int>? entryIds}) {
    final q = select(attachments)
      ..where(
        (a) =>
            a.fileName.like('%.jpg') |
            a.fileName.like('%.jpeg') |
            a.fileName.like('%.png') |
            a.fileName.like('%.webp'),
      );
    if (entryIds != null) q.where((a) => a.entryId.isIn(entryIds));
    return q.watch().map((rows) {
      final map = <int, String>{};
      for (final a in rows) {
        map.putIfAbsent(a.entryId, () => a.fileName);
      }
      return map;
    });
  }

  Future<int> addAttachment(int entryId, String fileName) => into(
    attachments,
  ).insert(AttachmentsCompanion.insert(entryId: entryId, fileName: fileName));

  Future<void> removeAttachment(int id) =>
      (delete(attachments)..where((a) => a.id.equals(id))).go();

  // -------------------------------------------------------------------------
  // Settings
  // -------------------------------------------------------------------------

  static const _dayEndsAtKey = 'day_ends_at_hour';

  /// Latest hour (0–[maxDayEndsAt]) up to which writing still belongs to the
  /// previous day. 0 = the day ends at midnight, the behaviour before this
  /// setting existed.
  static const maxDayEndsAt = 11;

  Stream<int> watchDayEndsAt() =>
      (select(
        settings,
      )..where((s) => s.key.equals(_dayEndsAtKey))).watchSingleOrNull().map(
        (row) => (int.tryParse(row?.value ?? '') ?? 0).clamp(0, maxDayEndsAt),
      );

  Future<void> setDayEndsAt(int hour) => into(settings).insertOnConflictUpdate(
    SettingsCompanion.insert(
      key: _dayEndsAtKey,
      value: '${hour.clamp(0, maxDayEndsAt)}',
    ),
  );

  // -------------------------------------------------------------------------
  // Throwback / "On this day"
  // -------------------------------------------------------------------------

  /// How many years back "on this day" looks. Well past a lifetime of
  /// journaling, and the date picker cannot reach further than year 2000.

  /// Entries from previous years whose entryDate falls on the same day + month
  /// as [today].
  ///
  /// Matching is a union of local-midnight day ranges, one per past year, so
  /// the comparison stays in local time and DST cannot shift a day.
  Stream<List<Entry>> watchThrowback(DateTime today) {
    return (select(entries)
          ..where(
            (e) =>
                _visible(e) &
                e.isDraft.equals(false) &
                e.monthDay.equals(monthDayOf(today)) &
                e.entryDate.isSmallerThanValue(DateTime(today.year)),
          )
          ..orderBy([(e) => OrderingTerm.desc(e.entryDate)]))
        .watch();
  }

  Stream<List<Entry>> watchMemories(String kind) {
    final now = DateTime.now();
    final q = select(entries)
      ..where((e) => _visible(e) & e.isDraft.equals(false));
    if (kind == 'first') {
      q.orderBy([(e) => OrderingTerm.asc(e.entryDate)]);
      q.limit(1);
    } else {
      final start = DateTime(
        now.year - 1,
        now.month,
        now.day - (now.weekday - 1),
      );
      final end = DateTime(start.year, start.month, start.day + 7);
      q.where(
        (e) =>
            e.entryDate.isBiggerOrEqualValue(start) &
            e.entryDate.isSmallerThanValue(end),
      );
      q.orderBy([(e) => OrderingTerm.desc(e.entryDate)]);
    }
    return q.watch();
  }

  // -------------------------------------------------------------------------
  // Calendar
  // -------------------------------------------------------------------------

  /// Entry counts per day for the given month, for calendar markers.
  /// Keys are local midnights, matching what the calendar grid asks for.
  Stream<Map<DateTime, int>> watchMonthCounts(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 1);
    return _watchEntryDates(
      (e) =>
          e.entryDate.isBiggerOrEqualValue(first) &
          e.entryDate.isSmallerThanValue(last),
    ).map((dates) {
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
          ..where(
            (e) =>
                _visible(e) &
                e.isDraft.equals(false) &
                e.entryDate.isBiggerOrEqualValue(start) &
                e.entryDate.isSmallerThanValue(end),
          )
          ..orderBy([(e) => OrderingTerm.desc(e.entryDate)]))
        .watch();
  }

  // -------------------------------------------------------------------------
  // Statistics
  // -------------------------------------------------------------------------

  /// entryDates of every non-draft entry, optionally narrowed by [filter].
  /// Only the date column is read, so bucketing in Dart stays cheap.
  Stream<List<DateTime>> _watchEntryDates([
    Expression<bool> Function($EntriesTable e)? filter,
  ]) {
    final q = selectOnly(entries)..addColumns([entries.entryDate]);
    q.where(
      _visible(entries) &
          entries.isDraft.equals(false) &
          (filter == null ? const Constant(true) : filter(entries)),
    );
    return q.watch().map(
      (rows) => [for (final r in rows) r.read(entries.entryDate)!],
    );
  }

  /// Streaks = consecutive calendar days with at least one entry.
  Stream<StreakInfo> watchStreaks() =>
      _watchEntryDates().map((dates) => computeStreaks(dates));

  Stream<GlobalStats> watchGlobalStats() {
    return customSelect(
      "SELECT "
      "(SELECT COUNT(*) FROM entries WHERE is_draft = 0 AND deleted_at IS NULL AND journal_id IN (SELECT id FROM journals WHERE deleted_at IS NULL)) AS total_entries, "
      "(SELECT COALESCE(SUM(word_count), 0) FROM entries WHERE is_draft = 0 AND deleted_at IS NULL AND journal_id IN (SELECT id FROM journals WHERE deleted_at IS NULL)) AS total_words, "
      "(SELECT COALESCE(SUM(writing_seconds), 0) FROM entries WHERE is_draft = 0 AND deleted_at IS NULL AND journal_id IN (SELECT id FROM journals WHERE deleted_at IS NULL)) AS total_seconds, "
      "(SELECT COUNT(*) FROM attachments JOIN entries ON entries.id = attachments.entry_id WHERE entries.deleted_at IS NULL AND entries.journal_id IN (SELECT id FROM journals WHERE deleted_at IS NULL)) AS total_attachments",
      readsFrom: {entries, attachments, journals},
    ).watchSingle().map((row) {
      final totalEntries = row.read<int>('total_entries');
      final totalWords = row.read<int>('total_words');
      return GlobalStats(
        totalEntries: totalEntries,
        totalWords: totalWords,
        totalWritingSeconds: row.read<int>('total_seconds'),
        totalAttachments: row.read<int>('total_attachments'),
        avgWordsPerEntry: totalEntries == 0 ? 0 : totalWords / totalEntries,
      );
    });
  }

  /// Entries per day over the 30 days ending today, oldest first. Entries
  /// dated in the future are left out — the chart only draws these 30 days.
  Stream<List<DayCount>> watchLast30DaysActivity() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 29);
    final end = DateTime(now.year, now.month, now.day + 1);
    return _watchEntryDates(
      (e) =>
          e.entryDate.isBiggerOrEqualValue(start) &
          e.entryDate.isSmallerThanValue(end),
    ).map((dates) {
      final counts = <DateTime, int>{};
      for (final date in dates) {
        counts.update(localDay(date), (c) => c + 1, ifAbsent: () => 1);
      }
      final days = counts.keys.toList()..sort();
      return [for (final day in days) DayCount(day, counts[day]!)];
    });
  }
}
