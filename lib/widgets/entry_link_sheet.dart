import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/database.dart';
import '../providers.dart';

final _linkResults = StreamProvider.autoDispose.family<List<Entry>, String>(
  (ref, query) =>
      ref.watch(databaseProvider).watchFeed(search: query, limit: 100),
);

Future<Entry?> showEntryLinkSheet(BuildContext context, {int? excludeId}) =>
    showModalBottomSheet<Entry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntryLinkSheet(excludeId: excludeId),
    );

class _EntryLinkSheet extends ConsumerStatefulWidget {
  const _EntryLinkSheet({this.excludeId});
  final int? excludeId;
  @override
  ConsumerState<_EntryLinkSheet> createState() => _EntryLinkSheetState();
}

class _EntryLinkSheetState extends ConsumerState<_EntryLinkSheet> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_linkResults(_query));
    return FractionallySizedBox(
      heightFactor: .8,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              const ListTile(title: Text('Link an entry')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Find an entry',
                    hintText: 'Search titles, writing or tags',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: results.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(
                    child: Text('Could not read entries. Try another search.'),
                  ),
                  data: (rows) {
                    final visible = rows
                        .where((e) => e.id != widget.excludeId)
                        .toList();
                    if (visible.isEmpty) {
                      return const Center(child: Text('No matching entries'));
                    }
                    return ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final e = visible[i];
                        return ListTile(
                          title: Text(
                            e.title.isEmpty ? 'Untitled entry' : e.title,
                          ),
                          subtitle: Text(
                            DateFormat.yMMMd().format(e.entryDate),
                          ),
                          onTap: () => Navigator.pop(context, e),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
