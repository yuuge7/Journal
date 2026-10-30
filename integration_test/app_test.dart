import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:journal/data/database.dart';
import 'package:journal/main.dart';
import 'package:journal/providers.dart';
import 'package:journal/screens/editor_screen.dart';
import 'package:journal/services/attachment_service.dart';
import 'package:journal/services/backup_service.dart';
import 'package:journal/services/platform_service.dart';
import 'package:journal/services/readable_export_service.dart';
import 'package:journal/widgets/entry_row.dart';

class FaultDatabase extends AppDatabase {
  FaultDatabase() : super.withExecutor(NativeDatabase.memory());
  bool failWrites = false;
  @override
  Future<int> insertEntry(EntriesCompanion companion) => failWrites
      ? Future.error(StateError('Disk unavailable for test'))
      : super.insertEntry(companion);
  @override
  Future<void> updateEntry(int id, EntriesCompanion companion) => failWrites
      ? Future.error(StateError('Disk unavailable for test'))
      : super.updateEntry(id, companion);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'write, recover, search, undo, calendar, insights, settings and exports on Android',
    (tester) async {
      final db = FaultDatabase();
      final temp = await getTemporaryDirectory();
      final dir = await Directory(
        '${temp.path}/integration-attachments',
      ).create(recursive: true);
      final attachments = AttachmentService(directory: dir);
      final journal = (await db.select(db.journals).get()).first.id;
      final secondJournal = await db.createJournal('Travel', 0xFF3D7A9E, 'T');
      final now = DateTime.now();
      for (final days in [0, 1, 4, 120, 367]) {
        await db.insertEntry(
          EntriesCompanion.insert(
            journalId: journal,
            title: Value('Memory $days'),
            contentJson: '[{"insert":"A memory worth keeping.\\n"}]',
            plainText: const Value('A memory worth keeping.'),
            entryDate: DateTime(now.year, now.month, now.day - days),
            createdAt: Value(
              DateTime(
                now.year,
                now.month,
                now.day - days + (days == 4 ? 2 : 0),
                21,
              ),
            ),
            wordCount: const Value(4),
            writingSeconds: Value(300 + days),
            mood: Value(1 + days % 5),
          ),
        );
      }
      await db.ensureTag('outside');
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('qa-root'),
          child: ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              attachmentServiceProvider.overrideWithValue(attachments),
            ],
            child: const JournalApp(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('Write').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.text('Start with a template'), findsNothing);
      await tester.enterText(
        find.byType(TextField).first,
        'Emulator field notes',
      );
      final quill = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      quill.replaceText(
        0,
        0,
        'A quiet walk by the river. ',
        const TextSelection.collapsed(offset: 26),
      );
      await tester.pump(const Duration(seconds: 3));
      debugPrint('QA DRAFT');
      final draft = (await db.watchFeed(search: 'field').first).single;
      expect(draft.wordCount, 6);
      expect(draft.isDraft, true);
      db.failWrites = true;
      quill.replaceText(quill.document.length - 1, 0, 'Keep this text.', null);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Save failed · retry'), findsOneWidget);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EditorScreen), findsOneWidget);
      db.failWrites = false;
      await tester.tap(find.text('Save failed · retry'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        (await db.getEntry(draft.id))!.plainText,
        contains('Keep this text.'),
      );
      debugPrint('QA PAUSE');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(seconds: 2));
      debugPrint('QA PAUSED_READ');
      final paused = (await db.getEntry(draft.id))!.writingSeconds;
      await Future<void>.delayed(const Duration(seconds: 2));
      expect((await db.getEntry(draft.id))!.writingSeconds, paused);
      debugPrint('QA RESUME');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 200));
      debugPrint('QA MENU');
      await tester.tap(find.byTooltip('Entry actions'));
      await tester.pump(const Duration(milliseconds: 300));
      debugPrint('QA FOCUS');
      await tester.tap(find.text('Focus mode'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(QuillSimpleToolbar), findsNothing);
      await tester.tap(find.text('Tap to show controls'));
      await tester.pump(const Duration(milliseconds: 300));
      debugPrint('QA MENU');
      await tester.tap(find.byTooltip('Entry actions'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Save as template'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await db.setting('templates'), contains('Emulator field notes'));
      // Inline tags and markdown use the same controller changes as keyboard input.
      quill.replaceText(
        0,
        quill.document.length - 1,
        '#out',
        const TextSelection.collapsed(offset: 4),
      );
      quill.updateSelection(
        const TextSelection.collapsed(offset: 4),
        ChangeSource.local,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('#outside').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect((await db.tagsForEntry(draft.id)).single.name, 'outside');
      quill.replaceText(
        0,
        quill.document.length - 1,
        '# ',
        const TextSelection.collapsed(offset: 2),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(quill.document.toDelta().toJson().toString(), contains('header'));
      quill.replaceText(
        0,
        quill.document.length - 1,
        'A quiet walk by the river. ',
        const TextSelection.collapsed(offset: 26),
      );
      debugPrint('QA MENU');
      await tester.tap(find.byTooltip('Entry actions'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Link another entry'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Memory 1').last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        quill.document.toDelta().toJson().toString(),
        contains('journal://entry/'),
      );
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(seconds: 1));
      final saved = (await db.getEntry(draft.id))!;
      expect(saved.isDraft, false);
      expect(saved.writingSeconds, greaterThanOrEqualTo(paused));
      expect(find.text('Emulator field notes'), findsOneWidget);
      debugPrint('QA SCREENSHOTS');
      await tester.pump();
      Future<void> screenshot(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('qa-root')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${temp.path}/qa-$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        binding.reportData ??= {};
        (binding.reportData!.putIfAbsent('screenshots', () => <dynamic>[])
                as List)
            .add({
              'screenshotName': name,
              'bytes': data.buffer.asUint8List().toList(),
            });
        image.dispose();
      }

      await screenshot('feed');
      await tester.tap(find.byTooltip('Search entries'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'outside');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Emulator field notes'), findsOneWidget);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pump(const Duration(milliseconds: 500));
      final row = find.ancestor(
        of: find.text('Emulator field notes'),
        matching: find.byType(EntryRow),
      );
      await tester.drag(row, const Offset(-400, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect((await db.getEntry(draft.id))!.deletedAt, isNotNull);
      await tester.tap(find.text('Undo'));
      await tester.pump(const Duration(milliseconds: 500));
      expect((await db.getEntry(draft.id))!.deletedAt, isNull);
      await tester.tap(find.text('Calendar').last);
      await tester.pump(const Duration(milliseconds: 500));
      await screenshot('calendar');
      await tester.tap(find.byTooltip('Year heat map'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('time at the page'), findsOneWidget);
      await screenshot('year');
      await tester.tap(find.text('Oct').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Progress').last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Your writing'), findsOneWidget);
      await screenshot('stats');
      await tester.tap(find.text('Settings').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Theme').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Light').last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(await db.setting('theme'), 'light');
      await screenshot('settings');
      await PlatformService.secure(true);
      await PlatformService.secure(false);
      expect(await PlatformService.call<String>('version'), isNotEmpty);
      await PlatformService.widget(streak: 2, written: true);
      await PlatformService.reminders(7);
      await PlatformService.reminders(0);
      debugPrint('QA VOICE');
      final voicePath = await PlatformService.startRecording();
      await tester.pump(const Duration(seconds: 2));
      expect(await PlatformService.stopRecording(), voicePath);
      final voiceName = await attachments.storeFile(voicePath!);
      await db.addAttachment(draft.id, voiceName);
      expect(
        await (await attachments.fileFor(voiceName)).length(),
        greaterThan(0),
      );
      await PlatformService.play((await attachments.fileFor(voiceName)).path);
      debugPrint('QA BACKUP');
      final backup = BackupService(db, attachments, tempDirectory: temp);
      final file = await backup.export('emulator test password');
      expect(await backup.import(file, 'emulator test password'), 0);
      final readable = ReadableExportService(db, attachments);
      final markdown = await readable.markdown();
      expect(await markdown.length(), greaterThan(100));
      final pdf = await readable.pdf();
      expect(String.fromCharCodes((await pdf.readAsBytes()).take(4)), '%PDF');
      await db.bulkMove({draft.id}, secondJournal);
      await db.bulkTag({draft.id}, 'tested');
      await db.archiveJournal(secondJournal, true);
      expect(
        (await db.watchJournals().first).any((j) => j.id == secondJournal),
        false,
      );
      await db.archiveJournal(secondJournal, false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await db.close();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
