import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'services/attachment_service.dart';
import 'services/backup_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final attachmentServiceProvider =
    Provider<AttachmentService>((ref) => AttachmentService());

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
    ref.watch(databaseProvider), ref.watch(attachmentServiceProvider)));

// ---------------------------------------------------------------------------
// Feed state
// ---------------------------------------------------------------------------

/// null = all journals.
class SelectedJournalNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void select(int? id) => state = id;
}

final selectedJournalProvider =
    NotifierProvider<SelectedJournalNotifier, int?>(SelectedJournalNotifier.new);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String query) => state = query;
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

// ---------------------------------------------------------------------------
// Streams from the database
// ---------------------------------------------------------------------------

final journalsProvider = StreamProvider<List<Journal>>(
    (ref) => ref.watch(databaseProvider).watchJournals());

final feedProvider = StreamProvider<List<Entry>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchFeed(
    journalId: ref.watch(selectedJournalProvider),
    search: ref.watch(searchQueryProvider),
  );
});

final tagsProvider =
    StreamProvider<List<Tag>>((ref) => ref.watch(databaseProvider).watchTags());

final tagsByEntryProvider = StreamProvider<Map<int, List<Tag>>>(
    (ref) => ref.watch(databaseProvider).watchTagsByEntry());

final thumbnailsProvider = StreamProvider<Map<int, String>>(
    (ref) => ref.watch(databaseProvider).watchThumbnails());

final throwbackProvider = StreamProvider<List<Entry>>(
    (ref) => ref.watch(databaseProvider).watchThrowback(DateTime.now()));

/// Key must be normalized to the first day of the month.
final monthCountsProvider = StreamProvider.family<Map<DateTime, int>, DateTime>(
    (ref, month) => ref.watch(databaseProvider).watchMonthCounts(month));

final entriesOnDayProvider = StreamProvider.family<List<Entry>, DateTime>(
    (ref, day) => ref.watch(databaseProvider).watchEntriesOn(day));

final streaksProvider = StreamProvider<StreakInfo>(
    (ref) => ref.watch(databaseProvider).watchStreaks());

final globalStatsProvider = StreamProvider<GlobalStats>(
    (ref) => ref.watch(databaseProvider).watchGlobalStats());

final activityProvider = StreamProvider<List<DayCount>>(
    (ref) => ref.watch(databaseProvider).watchLast30DaysActivity());
