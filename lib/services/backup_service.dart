import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import 'attachment_service.dart';

/// Full backup = ZIP (manifest + journals + tags + entries.ndjson + images/)
/// wrapped in a password-encrypted chunked AES-256-GCM container.
///
/// Container layout:
///   magic "MJRNLv1\x00" (8B) | salt (16B) | iterations (4B BE) |
///   repeated chunks: cipherLen (4B BE) | nonce (12B) | cipherText | mac (16B)
///
/// Entries are written/read as NDJSON so both export and import stream one
/// entry at a time instead of materializing the whole dataset in memory.
class BackupService {
  BackupService(this.db, this.attachmentService);

  final AppDatabase db;
  final AttachmentService attachmentService;

  static const _magic = 'MJRNLv1\x00';
  static const _iterations = 210000;
  static const _chunkSize = 1024 * 1024; // 1 MiB plaintext per chunk
  static const _pageSize = 200; // entries per DB page while streaming

  final _aes = AesGcm.with256bits();

  Future<SecretKey> _deriveKey(String password, List<int> salt,
      {int iterations = _iterations}) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  // ---------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------

  /// Builds the encrypted backup and returns the file, ready to be shared.
  Future<File> export(String password, {void Function(String)? onProgress}) async {
    final tmp = await getTemporaryDirectory();
    final work = await Directory(p.join(tmp.path, 'backup_work')).create(recursive: true);
    final zipFile = File(p.join(tmp.path, 'backup_plain.zip'));

    try {
      onProgress?.call('Collecting data…');
      final journals = await db.select(db.journals).get();
      final tags = await db.select(db.tags).get();

      // entries.ndjson — stream DB pages into the file.
      final ndjson = File(p.join(work.path, 'entries.ndjson'));
      final sink = ndjson.openWrite();
      var entryCount = 0;
      try {
        while (true) {
          final page = await (db.select(db.entries)
                ..orderBy([(e) => OrderingTerm.asc(e.id)])
                ..limit(_pageSize, offset: entryCount))
              .get();
          if (page.isEmpty) break;
          for (final e in page) {
            final tagIds = (await db.tagsForEntry(e.id)).map((t) => t.id).toList();
            final files =
                (await db.attachmentsForEntry(e.id)).map((a) => a.fileName).toList();
            sink.writeln(jsonEncode({
              'journalId': e.journalId,
              'title': e.title,
              'contentJson': e.contentJson,
              'plainText': e.plainText,
              'entryDate': e.entryDate.toIso8601String(),
              'createdAt': e.createdAt.toIso8601String(),
              'updatedAt': e.updatedAt.toIso8601String(),
              'wordCount': e.wordCount,
              'writingSeconds': e.writingSeconds,
              'mood': e.mood,
              'isDraft': e.isDraft,
              'tagIds': tagIds,
              'attachments': files,
            }));
          }
          entryCount += page.length;
          onProgress?.call('Exported $entryCount entries…');
        }
      } finally {
        await sink.close();
      }

      final manifest = {
        'format': 'modern-journal-backup',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'entryCount': entryCount,
      };
      await File(p.join(work.path, 'manifest.json')).writeAsString(jsonEncode(manifest));
      await File(p.join(work.path, 'journals.json')).writeAsString(jsonEncode([
        for (final j in journals)
          {'id': j.id, 'name': j.name, 'color': j.color, 'emoji': j.emoji}
      ]));
      await File(p.join(work.path, 'tags.json')).writeAsString(jsonEncode([
        for (final t in tags) {'id': t.id, 'name': t.name}
      ]));

      onProgress?.call('Building archive…');
      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path);
      await encoder.addFile(File(p.join(work.path, 'manifest.json')), 'manifest.json');
      await encoder.addFile(File(p.join(work.path, 'journals.json')), 'journals.json');
      await encoder.addFile(File(p.join(work.path, 'tags.json')), 'tags.json');
      await encoder.addFile(ndjson, 'entries.ndjson');
      final attachDir = await attachmentService.attachmentsDir();
      await for (final f in attachDir.list()) {
        if (f is File) {
          await encoder.addFile(f, 'images/${p.basename(f.path)}');
        }
      }
      await encoder.close();

      onProgress?.call('Encrypting…');
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final outFile = File(p.join(tmp.path, 'journal-backup-$stamp.mjbackup'));
      await _encryptFile(zipFile, outFile, password);
      return outFile;
    } finally {
      if (await zipFile.exists()) await zipFile.delete();
      await work.delete(recursive: true);
    }
  }

  Future<void> _encryptFile(File input, File output, String password) async {
    final salt = _aes.newNonce(); // 12B — extend to 16 with more randomness
    final salt16 = <int>[...salt, ...SecretKeyData.random(length: 4).bytes];
    final key = await _deriveKey(password, salt16);

    final out = output.openWrite();
    try {
      out.add(ascii.encode(_magic));
      out.add(salt16);
      out.add(_be32(_iterations));

      final raf = await input.open();
      try {
        while (true) {
          final chunk = await raf.read(_chunkSize);
          if (chunk.isEmpty) break;
          final box = await _aes.encrypt(chunk, secretKey: key);
          out.add(_be32(box.cipherText.length));
          out.add(box.nonce);
          out.add(box.cipherText);
          out.add(box.mac.bytes);
        }
      } finally {
        await raf.close();
      }
    } finally {
      await out.close();
    }
  }

  // ---------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------

  /// Decrypts and merges a backup file into the current database.
  /// Journals/tags are matched by name; entries are always inserted as new.
  /// Returns the number of imported entries.
  Future<int> import(File backup, String password,
      {void Function(String)? onProgress}) async {
    final tmp = await getTemporaryDirectory();
    final zipFile = File(p.join(tmp.path, 'restore_plain.zip'));
    final extractDir = Directory(p.join(tmp.path, 'restore_work'));

    try {
      onProgress?.call('Decrypting…');
      await _decryptFile(backup, zipFile, password);

      onProgress?.call('Unpacking archive…');
      if (await extractDir.exists()) await extractDir.delete(recursive: true);
      await extractFileToDisk(zipFile.path, extractDir.path);

      final manifestFile = File(p.join(extractDir.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw const FormatException('Not a journal backup: manifest missing');
      }
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      if (manifest['format'] != 'modern-journal-backup') {
        throw const FormatException('Unknown backup format');
      }

      // Journal + tag ID remapping (match by name, create when missing).
      final journalMap = <int, int>{};
      final journalsJson = jsonDecode(
              await File(p.join(extractDir.path, 'journals.json')).readAsString())
          as List<dynamic>;
      final existingJournals = await db.select(db.journals).get();
      for (final j in journalsJson.cast<Map<String, dynamic>>()) {
        final match = existingJournals
            .where((e) => e.name == j['name'])
            .firstOrNull;
        journalMap[j['id'] as int] = match?.id ??
            await db.createJournal(
                j['name'] as String, j['color'] as int, j['emoji'] as String);
      }

      final tagMap = <int, int>{};
      final tagsJson = jsonDecode(
              await File(p.join(extractDir.path, 'tags.json')).readAsString())
          as List<dynamic>;
      for (final t in tagsJson.cast<Map<String, dynamic>>()) {
        tagMap[t['id'] as int] = await db.ensureTag(t['name'] as String);
      }

      // Copy images before entries so attachment rows always point at files.
      final imagesDir = Directory(p.join(extractDir.path, 'images'));
      final attachDir = await attachmentService.attachmentsDir();
      if (await imagesDir.exists()) {
        await for (final f in imagesDir.list()) {
          if (f is File) {
            await f.copy(p.join(attachDir.path, p.basename(f.path)));
          }
        }
      }

      // Stream entries.ndjson line by line — one JSON parse per entry.
      onProgress?.call('Importing entries…');
      var imported = 0;
      final lines = File(p.join(extractDir.path, 'entries.ndjson'))
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await db.transaction(() async {
        await for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final e = jsonDecode(line) as Map<String, dynamic>;
          final journalId = journalMap[e['journalId'] as int];
          if (journalId == null) continue;
          final entryId = await db.insertEntry(EntriesCompanion.insert(
            journalId: journalId,
            title: Value(e['title'] as String? ?? ''),
            contentJson: e['contentJson'] as String,
            plainText: Value(e['plainText'] as String? ?? ''),
            entryDate: DateTime.parse(e['entryDate'] as String),
            createdAt: Value(DateTime.parse(e['createdAt'] as String)),
            updatedAt: Value(DateTime.parse(e['updatedAt'] as String)),
            wordCount: Value(e['wordCount'] as int? ?? 0),
            writingSeconds: Value(e['writingSeconds'] as int? ?? 0),
            mood: Value(e['mood'] as int?),
            isDraft: Value(e['isDraft'] as bool? ?? false),
          ));
          final tagIds = (e['tagIds'] as List<dynamic>? ?? [])
              .map((t) => tagMap[t as int])
              .whereType<int>()
              .toList();
          if (tagIds.isNotEmpty) await db.setEntryTags(entryId, tagIds);
          for (final fileName in (e['attachments'] as List<dynamic>? ?? [])) {
            await db.addAttachment(entryId, fileName as String);
          }
          imported++;
          if (imported % 100 == 0) onProgress?.call('Imported $imported entries…');
        }
      });
      return imported;
    } finally {
      if (await zipFile.exists()) await zipFile.delete();
      if (await extractDir.exists()) await extractDir.delete(recursive: true);
    }
  }

  Future<void> _decryptFile(File input, File output, String password) async {
    final raf = await input.open();
    final out = output.openWrite();
    try {
      final magic = await raf.read(_magic.length);
      if (ascii.decode(magic, allowInvalid: true) != _magic) {
        throw const FormatException('Not a journal backup file');
      }
      final salt = await raf.read(16);
      final iterations = _readBe32(await raf.read(4));
      final key = await _deriveKey(password, salt, iterations: iterations);

      while (true) {
        final lenBytes = await raf.read(4);
        if (lenBytes.isEmpty) break;
        final cipherLen = _readBe32(lenBytes);
        final nonce = await raf.read(12);
        final cipherText = await raf.read(cipherLen);
        final mac = await raf.read(16);
        final List<int> plain;
        try {
          plain = await _aes.decrypt(
            SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
            secretKey: key,
          );
        } on SecretBoxAuthenticationError {
          throw const WrongPasswordException();
        }
        out.add(plain);
      }
    } finally {
      await raf.close();
      await out.close();
    }
  }

  static Uint8List _be32(int v) => Uint8List(4)
    ..buffer.asByteData().setUint32(0, v);

  static int _readBe32(List<int> b) =>
      Uint8List.fromList(b).buffer.asByteData().getUint32(0);
}

class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'Wrong password or corrupted backup';
}
