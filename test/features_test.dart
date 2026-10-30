import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';
import 'package:journal/services/attachment_service.dart';
import 'package:journal/services/backup_service.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late AttachmentService attachments;
  late int journal;
  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('journal_features');
    attachments = AttachmentService(
      directory: await Directory('${temp.path}/attachments').create(),
    );
    journal = (await db.watchJournals().first).first.id;
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<int> entry({
    String text = 'A quiet afternoon',
    String title = 'A page',
    DateTime? day,
  }) => db.insertEntry(
    EntriesCompanion.insert(
      journalId: journal,
      contentJson: '[{"insert":"$text\\n"}]',
      plainText: Value(text),
      title: Value(title),
      entryDate: day ?? DateTime(2026, 10, 30),
      wordCount: Value(countWords(text)),
    ),
  );

  test(
    'version 1 backups remain readable and deduplicate on repeat import',
    () async {
      final work = await Directory('${temp.path}/legacy').create();
      final content = <String, dynamic>{
        'manifest.json': {
          'format': 'modern-journal-backup',
          'version': 1,
          'entryCount': 1,
        },
        'journals.json': [
          {'id': 1, 'name': 'Old notebook', 'color': 1, 'emoji': 'J'},
        ],
        'tags.json': [],
      };
      final archive = File('${work.path}/legacy.zip');
      final encoder = ZipFileEncoder()..create(archive.path);
      for (final value in content.entries) {
        final file = await File(
          '${work.path}/${value.key}',
        ).writeAsString(jsonEncode(value.value));
        await encoder.addFile(file, value.key);
      }
      final ndjson = await File('${work.path}/entries.ndjson').writeAsString(
        jsonEncode({
          'journalId': 1,
          'contentJson': '[{"insert":"An older page\\n"}]',
          'plainText': 'An older page',
          'entryDate': '2025-08-12T00:00:00.000',
          'createdAt': '2025-08-15T21:00:00.000',
          'updatedAt': '2025-08-15T21:00:00.000',
        }),
      );
      await encoder.addFile(ndjson, 'entries.ndjson');
      await encoder.close();
      final salt = List<int>.generate(16, (i) => i);
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 210000,
        bits: 256,
      ).deriveKeyFromPassword(password: 'legacy password', nonce: salt);
      final box = await AesGcm.with256bits().encrypt(
        await archive.readAsBytes(),
        secretKey: key,
      );
      List<int> be32(int n) =>
          (Uint8List(4)..buffer.asByteData().setUint32(0, n));
      final file = await File('${work.path}/legacy.mjbackup').writeAsBytes([
        ...ascii.encode('MJRNLv1\x00'),
        ...salt,
        ...be32(210000),
        ...be32(box.cipherText.length),
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
      final service = BackupService(db, attachments, tempDirectory: temp);
      expect(await service.import(file, 'legacy password'), 1);
      expect(await service.import(file, 'legacy password'), 0);
      final entry = (await db.watchFeed().first).single;
      expect(entry.wordCount, 3);
      expect(entry.entryDate, DateTime(2025, 8, 12));
    },
  );

  test(
    'delete, undo and journal bin preserve attachments and exclude statistics',
    () async {
      final id = await entry();
      await (await attachments.fileFor('photo.jpg')).writeAsBytes([1, 2, 3]);
      await db.addAttachment(id, 'photo.jpg');
      await db.deleteEntry(id);
      expect(await db.watchFeed().first, isEmpty);
      expect((await db.watchGlobalStats().first).totalEntries, 0);
      expect((await db.watchBin().first).single.id, id);
      await db.restoreEntry(id);
      expect((await db.watchFeed().first).single.id, id);
      await db.deleteJournal(journal);
      expect(await db.watchFeed().first, isEmpty);
      expect((await db.attachmentsForEntry(id)).length, 1);
      await db.restoreJournal(journal);
      expect((await db.watchGlobalStats().first).totalEntries, 1);
      expect(await (await attachments.fileFor('photo.jpg')).exists(), true);
    },
  );
  test(
    'only bin records older than thirty days are purged and orphan files are swept',
    () async {
      final old = await entry(), recent = await entry();
      await db.updateEntry(
        old,
        EntriesCompanion(
          deletedAt: Value(DateTime.now().subtract(const Duration(days: 31))),
        ),
      );
      await db.deleteEntry(recent);
      await (await attachments.fileFor('orphan.m4a')).writeAsBytes([1]);
      await db.purgeBin();
      expect(await db.getEntry(old), isNull);
      expect(await db.getEntry(recent), isNotNull);
      await attachments.sweep({});
      expect(await (await attachments.fileFor('orphan.m4a')).exists(), false);
    },
  );
  test(
    'FTS finds prefixes, tags, Unicode and scopes without interpreting SQL',
    () async {
      final id = await entry(
        text: 'Plimbare dimineață by the river',
        title: 'Walking home',
      );
      final tag = await db.ensureTag('outdoors');
      await db.setEntryTags(id, [tag]);
      expect((await db.watchFeed(search: 'dimin').first).single.id, id);
      expect((await db.watchFeed(search: '#outdoors').first).single.id, id);
      expect(
        await db.watchFeed(search: 'river', titlesOnly: true).first,
        isEmpty,
      );
      expect(
        (await db.watchFeed(search: 'walk', titlesOnly: true).first).single.id,
        id,
      );
      expect(await db.watchFeed(search: "' OR 1=1 --").first, isEmpty);
      expect(await db.watchFeed(search: 'walk', year: 2025).first, isEmpty);
      await db.updateEntry(
        id,
        const EntriesCompanion(plainText: Value('Changed text')),
      );
      expect(await db.watchFeed(search: 'river').first, isEmpty);
    },
  );
  test(
    'feed paging, local month-day, bulk tag/move and archive order',
    () async {
      final id = await entry(day: DateTime(2025, 10, 30, 0, 15));
      await entry();
      expect(await db.watchFeed(limit: 1).first, hasLength(1));
      expect(
        (await db.watchThrowback(DateTime(2026, 10, 30)).first).single.id,
        id,
      );
      final other = await db.createJournal('Travel', 1, 'T');
      await db.bulkMove({id}, other);
      await db.bulkTag({id}, 'memory');
      expect((await db.tagsForEntry(id)).single.name, 'memory');
      await db.archiveJournal(other, true);
      expect((await db.watchJournals().first).any((j) => j.id == other), false);
      expect(
        (await db.watchJournals(includeArchived: true).first).any(
          (j) => j.id == other,
        ),
        true,
      );
      await db.reorderJournals([other, journal]);
      expect(
        (await db.watchJournals(includeArchived: true).first).first.id,
        other,
      );
    },
  );
  test(
    'encrypted backup round trip verifies, skips duplicates and replaces by stable ID',
    () async {
      final id = await entry();
      await db.updateEntry(
        id,
        const EntriesCompanion(location: Value('44.4, 26.1')),
      );
      final service = BackupService(db, attachments, tempDirectory: temp);
      final progress = <double>[];
      final file = await service.export(
        'test password',
        onProgress: (p) => progress.add(p.fraction),
      );
      expect(progress.last, 1);
      expect(await service.import(file, 'test password'), 0);
      await db.updateEntry(id, const EntriesCompanion(title: Value('Changed')));
      expect(
        await service.import(
          file,
          'test password',
          duplicates: DuplicatePolicy.replace,
        ),
        1,
      );
      expect((await db.getEntry(id))!.title, 'A page');
      expect((await db.getEntry(id))!.location, '44.4, 26.1');
      final restoredDb = AppDatabase.withExecutor(NativeDatabase.memory());
      try {
        expect(
          await BackupService(
            restoredDb,
            attachments,
            tempDirectory: temp,
          ).import(file, 'test password'),
          1,
        );
        expect(
          (await restoredDb.watchFeed().first).single.stableId,
          (await db.getEntry(id))!.stableId,
        );
      } finally {
        await restoredDb.close();
      }
    },
  );
  test(
    'backup rejects wrong password, bit flips, invalid file and truncation without writes',
    () async {
      await entry();
      final service = BackupService(db, attachments, tempDirectory: temp);
      final file = await service.export('correct password');
      await expectLater(
        service.import(file, 'wrong password'),
        throwsA(isA<WrongPasswordException>()),
      );
      final bytes = await file.readAsBytes();
      final broken = File('${temp.path}/broken.mjbackup');
      await broken.writeAsBytes(bytes.sublist(0, bytes.length - 32));
      await expectLater(
        service.import(broken, 'correct password'),
        throwsA(isA<FormatException>()),
      );
      final changed = [...bytes];
      changed[70] ^= 1;
      await broken.writeAsBytes(changed);
      await expectLater(
        service.import(broken, 'correct password'),
        throwsA(isA<FormatException>()),
      );
      await broken.writeAsString('not a backup');
      await expectLater(
        service.import(broken, 'correct password'),
        throwsA(isA<FormatException>()),
      );
      expect(await db.watchFeed().first, hasLength(1));
    },
  );
}
