import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

class BinScreen extends ConsumerWidget {
  const BinScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(binProvider).value ?? [];
    final journals = ref.watch(deletedJournalsProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Recently deleted')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'You can restore entries and notebooks for 30 days. After that, they are removed from this device.',
            ),
          ),
          for (final j in journals)
            ListTile(
              leading: Text(j.emoji),
              title: Text(j.name),
              subtitle: const Text('Notebook and all its entries'),
              trailing: TextButton(
                onPressed: () =>
                    ref.read(databaseProvider).restoreJournal(j.id),
                child: const Text('Restore'),
              ),
            ),
          for (final e in entries)
            ListTile(
              title: Text(e.title.isEmpty ? 'Untitled entry' : e.title),
              subtitle: Text(
                'Deleted ${e.deletedAt!.toLocal().toString().substring(0, 10)}',
              ),
              trailing: TextButton(
                onPressed: () => ref.read(databaseProvider).restoreEntry(e.id),
                child: const Text('Restore'),
              ),
            ),
          if (entries.isEmpty && journals.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('The bin is empty.'),
            ),
        ],
      ),
    );
  }
}
