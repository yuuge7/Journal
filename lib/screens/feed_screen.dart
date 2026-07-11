import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../providers.dart';
import '../widgets/entry_card.dart';
import 'journals_screen.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final throwback = ref.watch(throwbackProvider).value ?? const <Entry>[];
    final journals = ref.watch(journalsProvider).value ?? const <Journal>[];
    final selected = ref.watch(selectedJournalProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Search entries…', border: InputBorder.none),
                onChanged: (q) =>
                    ref.read(searchQueryProvider.notifier).set(q),
              )
            : const Text('Journal'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _searchController.clear();
                ref.read(searchQueryProvider.notifier).set('');
              }
            },
          ),
          IconButton(
            tooltip: 'Manage journals',
            icon: const Icon(Icons.library_books_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const JournalsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          if (journals.length > 1)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: selected == null,
                      onSelected: (_) => ref
                          .read(selectedJournalProvider.notifier)
                          .select(null),
                    ),
                  ),
                  for (final j in journals)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        avatar: Text(j.emoji),
                        label: Text(j.name),
                        selected: selected == j.id,
                        onSelected: (_) => ref
                            .read(selectedJournalProvider.notifier)
                            .select(selected == j.id ? null : j.id),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: feed.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (entries) {
                if (entries.isEmpty && throwback.isEmpty) {
                  return const _EmptyFeed();
                }
                // ListView.builder keeps the feed cheap even with thousands
                // of entries. Index 0 is reserved for the throwback banner.
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 96),
                  itemCount: entries.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return throwback.isEmpty
                          ? const SizedBox.shrink()
                          : _ThrowbackBanner(entries: throwback);
                    }
                    return EntryCard(entry: entries[i - 1], showYear: true);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('📖', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        Text('No entries yet',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Tap + to write your first one',
            style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}

/// "On this day" — entries from the same day+month in previous years.
class _ThrowbackBanner extends StatelessWidget {
  const _ThrowbackBanner({required this.entries});
  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              const Text('🕰️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('On this day',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer)),
              const Spacer(),
              Text('${entries.length} ${entries.length == 1 ? "memory" : "memories"}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer)),
            ]),
          ),
          const SizedBox(height: 6),
          for (final e in entries.take(3)) EntryCard(entry: e, showYear: true),
          if (entries.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 2),
              child: Text('+ ${entries.length - 3} more',
                  style: theme.textTheme.labelSmall),
            ),
        ]),
      ),
    );
  }
}
