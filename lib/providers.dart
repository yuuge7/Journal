import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'services/attachment_service.dart';
import 'services/backup_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final attachmentServiceProvider = Provider<AttachmentService>(
  (ref) => AttachmentService(),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(databaseProvider),
    ref.watch(attachmentServiceProvider),
  ),
);

// ---------------------------------------------------------------------------
// Feed state
// ---------------------------------------------------------------------------

/// null = all journals.
class SelectedJournalNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void select(int? id) => state = id;
}

final selectedJournalProvider = NotifierProvider<SelectedJournalNotifier, int?>(
  SelectedJournalNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

// ---------------------------------------------------------------------------
// Streams from the database
// ---------------------------------------------------------------------------

final journalsProvider = StreamProvider<List<Journal>>(
  (ref) => ref.watch(databaseProvider).watchJournals(),
);

final feedProvider = StreamProvider<List<Entry>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchFeed(
    journalId: ref.watch(selectedJournalProvider),
    search: ref.watch(searchQueryProvider),
    titlesOnly: ref.watch(titlesOnlyProvider),
    year: ref.watch(thisYearProvider) ? DateTime.now().year : null,
    limit: ref.watch(feedLimitProvider),
    before: ref.watch(feedBeforeProvider),
  );
});

final tagsProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(databaseProvider).watchTags(),
);

final throwbackProvider = StreamProvider<List<Entry>>(
  (ref) => ref.watch(databaseProvider).watchThrowback(DateTime.now()),
);
final latestDraftProvider = StreamProvider<Entry?>(
  (ref) => ref.watch(databaseProvider).watchLatestDraft(),
);

/// Key must be normalized to the first day of the month.
final monthCountsProvider = StreamProvider.family<Map<DateTime, int>, DateTime>(
  (ref, month) => ref.watch(databaseProvider).watchMonthCounts(month),
);

final entriesOnDayProvider = StreamProvider.family<List<Entry>, DateTime>(
  (ref, day) => ref.watch(databaseProvider).watchEntriesOn(day),
);

final streaksProvider = StreamProvider<StreakInfo>(
  (ref) => ref.watch(databaseProvider).watchStreaks(),
);

final globalStatsProvider = StreamProvider<GlobalStats>(
  (ref) => ref.watch(databaseProvider).watchGlobalStats(),
);

final activityProvider = StreamProvider<List<DayCount>>(
  (ref) => ref.watch(databaseProvider).watchLast30DaysActivity(),
);

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// Hour until which writing still counts as the previous day. 0 = midnight.
final dayEndsAtProvider = StreamProvider<int>(
  (ref) => ref.watch(databaseProvider).watchDayEndsAt(),
);

class Toggle extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void reset() => state = false;
}

final titlesOnlyProvider = NotifierProvider<Toggle, bool>(Toggle.new);
final thisYearProvider = NotifierProvider<Toggle, bool>(Toggle.new);

class FeedLimit extends Notifier<int> {
  @override
  int build() => 200;
  void more() => state += 200;
}

final feedLimitProvider = NotifierProvider<FeedLimit, int>(FeedLimit.new);

class FeedBefore extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void set(DateTime? day) => state = day;
}

final feedBeforeProvider = NotifierProvider<FeedBefore, DateTime?>(
  FeedBefore.new,
);
final preferenceProvider = StreamProvider.family<String?, String>(
  (ref, key) => ref.watch(databaseProvider).watchSetting(key),
);
final allJournalsProvider = StreamProvider<List<Journal>>(
  (ref) => ref.watch(databaseProvider).watchJournals(includeArchived: true),
);
final insightsProvider = StreamProvider<List<EntryInsight>>(
  (ref) => ref.watch(databaseProvider).watchInsights(),
);
final heatProvider = StreamProvider.autoDispose.family<Map<DateTime, int>, int>(
  (ref, year) => ref.watch(databaseProvider).watchHeat(year),
);
final binProvider = StreamProvider<List<Entry>>(
  (ref) => ref.watch(databaseProvider).watchBin(),
);
final deletedJournalsProvider = StreamProvider<List<Journal>>(
  (ref) => ref.watch(databaseProvider).watchDeletedJournals(),
);
final memoriesProvider = StreamProvider.family<List<Entry>, String>(
  (ref, kind) => ref.watch(databaseProvider).watchMemories(kind),
);
final entryTagsProvider = StreamProvider.autoDispose.family<List<Tag>, int>(
  (ref, id) => ref
      .watch(databaseProvider)
      .watchTagsByEntry(entryIds: [id])
      .map((m) => m[id] ?? []),
);
final entryThumbProvider = StreamProvider.autoDispose.family<String?, int>(
  (ref, id) => ref
      .watch(databaseProvider)
      .watchThumbnails(entryIds: [id])
      .map((m) => m[id]),
);
final attachmentsForEntryProvider = StreamProvider.autoDispose
    .family<List<Attachment>, int>(
      (ref, id) => ref.watch(databaseProvider).watchAttachments(id),
    );
