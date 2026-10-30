import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';
import 'package:journal/providers.dart';
import 'package:journal/services/attachment_service.dart';
import 'package:journal/theme/app_theme.dart';
import 'package:journal/widgets/entry_row.dart';

void main() {
  testWidgets(
    'a photo with a short caption has a wide image at 320dp and 2x text',
    (tester) async {
      final db = AppDatabase.withExecutor(NativeDatabase.memory());
      final journal = (await db.select(db.journals).get()).first.id;
      final id = await db.insertEntry(
        EntriesCompanion.insert(
          journalId: journal,
          title: const Value('One photo'),
          contentJson: '[]',
          plainText: const Value('Mist over the water'),
          wordCount: const Value(4),
          entryDate: DateTime.now(),
        ),
      );
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('journal_photo_row'),
      ))!;
      await tester.runAsync(
        () => File('assets/icon/icon.png').copy('${dir.path}/photo.png'),
      );
      await db.addAttachment(id, 'photo.png');
      final entry = (await db.getEntry(id))!;
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            attachmentServiceProvider.overrideWithValue(
              AttachmentService(directory: dir),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(brightness: Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: EntryRow(entry: entry),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
      final image = tester.getSize(find.byType(Image));
      expect(image.width / image.height, greaterThan(1.5));
      expect(find.text('One photo'), findsOneWidget);
      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
