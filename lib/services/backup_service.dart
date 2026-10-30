import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';
import 'attachment_service.dart';

class BackupProgress {
  const BackupProgress(this.message, this.fraction);
  final String message;
  final double fraction;
}

enum DuplicatePolicy { skip, replace }

class BackupSummary {
  const BackupSummary(this.entries, this.attachments, this.bytes);
  final int entries, attachments, bytes;
}

/// Version 2 authenticates chunk order and an explicit end marker. Version 1
/// remains readable. All archive and database processing uses bounded pages.
class BackupService {
  BackupService(this.db, this.attachmentService, {this.tempDirectory});
  final AppDatabase db;
  final AttachmentService attachmentService;
  final Directory? tempDirectory;
  static const _magic = 'MJRNLv2\x00';
  static const _legacyMagic = 'MJRNLv1\x00';
  static const _iterations = 210000;
  static const _chunkSize = 1024 * 1024;
  final _aes = AesGcm.with256bits();
  Future<Directory> _work() async => Directory(
    p.join(
      (tempDirectory ?? await getTemporaryDirectory()).path,
      'journal-${const Uuid().v4()}',
    ),
  ).create(recursive: true);
  Future<SecretKey> _key(String password, List<int> salt, int iterations) =>
      Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);
  Future<List<int>> _verifier(SecretKey key) async =>
      (await Hmac.sha256().calculateMac(
        utf8.encode('Journal backup password v2'),
        secretKey: key,
      )).bytes.sublist(0, 16);

  Future<BackupSummary> summary() async {
    final count = db.entries.id.count();
    final row = await (db.selectOnly(
      db.entries,
    )..addColumns([count])).getSingle();
    final files = await db.select(db.attachments).get();
    var bytes = 0;
    for (final a in files) {
      final f = await attachmentService.fileFor(a.fileName);
      if (await f.exists()) bytes += await f.length();
    }
    return BackupSummary(row.read(count) ?? 0, files.length, bytes);
  }

  Future<File> export(
    String password, {
    void Function(BackupProgress)? onProgress,
  }) async {
    final work = await _work();
    final zip = File(p.join(work.path, 'plain.zip'));
    final total = await summary();
    final out = File(
      p.join(
        (tempDirectory ?? await getTemporaryDirectory()).path,
        'journal-${DateTime.now().millisecondsSinceEpoch}.mjbackup',
      ),
    );
    try {
      onProgress?.call(const BackupProgress('Collecting writing', .02));
      var count = 0, cursor = 0;
      final ndjson = File(p.join(work.path, 'entries.ndjson'));
      final sink = ndjson.openWrite();
      final referencedFiles = <String>{};
      try {
        while (true) {
          final page =
              await (db.select(db.entries)
                    ..where((e) => e.id.isBiggerThanValue(cursor))
                    ..orderBy([(e) => OrderingTerm.asc(e.id)])
                    ..limit(200))
                  .get();
          if (page.isEmpty) break;
          for (final e in page) {
            final files = (await db.attachmentsForEntry(
              e.id,
            )).map((a) => a.fileName).toList();
            referencedFiles.addAll(files);
            sink.writeln(
              jsonEncode({
                'stableId': e.stableId,
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
                'location': e.location,
                'deletedAt': e.deletedAt?.toIso8601String(),
                'tagIds': (await db.tagsForEntry(
                  e.id,
                )).map((t) => t.id).toList(),
                'attachments': files,
              }),
            );
            count++;
          }
          cursor = page.last.id;
          onProgress?.call(
            BackupProgress(
              'Collected $count entries',
              .05 + .35 * count / (total.entries == 0 ? 1 : total.entries),
            ),
          );
        }
      } finally {
        await sink.close();
      }
      final journals = await db.select(db.journals).get();
      final tags = await db.select(db.tags).get();
      final data = <String, dynamic>{
        'manifest.json': {
          'format': 'modern-journal-backup',
          'version': 2,
          'entryCount': count,
          'exportedAt': DateTime.now().toIso8601String(),
        },
        'journals.json': [
          for (final j in journals)
            {
              'id': j.id,
              'name': j.name,
              'color': j.color,
              'emoji': j.emoji,
              'archived': j.archived,
              'sortOrder': j.sortOrder,
              'deletedAt': j.deletedAt?.toIso8601String(),
            },
        ],
        'tags.json': [
          for (final t in tags) {'id': t.id, 'name': t.name},
        ],
      };
      final encoder = ZipFileEncoder();
      encoder.create(zip.path);
      try {
        for (final item in data.entries) {
          final file = await File(
            p.join(work.path, item.key),
          ).writeAsString(jsonEncode(item.value));
          await encoder.addFile(file, item.key);
        }
        await encoder.addFile(ndjson, 'entries.ndjson');
        for (final name in referencedFiles) {
          final file = await attachmentService.fileFor(name);
          if (!await file.exists()) {
            throw FormatException('Attachment is missing: $name');
          }
          await encoder.addFile(file, 'images/$name');
        }
      } finally {
        await encoder.close();
      }
      onProgress?.call(const BackupProgress('Encrypting backup', .55));
      await _encrypt(zip, out, password);
      onProgress?.call(const BackupProgress('Verifying encrypted backup', .8));
      final verify = File(p.join(work.path, 'verify.zip'));
      await _decrypt(out, verify, password);
      final verifyDir = Directory(p.join(work.path, 'verify'));
      await _extract(verify, verifyDir);
      final manifest =
          jsonDecode(
                await File(
                  p.join(verifyDir.path, 'manifest.json'),
                ).readAsString(),
              )
              as Map;
      if (manifest['entryCount'] != count) {
        throw const FormatException('Backup verification failed');
      }
      final actual = await File(p.join(verifyDir.path, 'entries.ndjson'))
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .length;
      if (actual != count) {
        throw const FormatException('Backup entry count does not match');
      }
      onProgress?.call(const BackupProgress('Backup verified', 1));
      return out;
    } catch (_) {
      if (await out.exists()) await out.delete();
      rethrow;
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<void> _encrypt(File input, File output, String password) async {
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await _key(password, salt, _iterations);
    final header = [
      ...ascii.encode(_magic),
      ...salt,
      ..._be32(_iterations),
      1,
      ...await _verifier(key),
    ];
    final sink = output.openWrite();
    final source = await input.open();
    try {
      sink.add(header);
      var index = 0;
      while (true) {
        final chunk = await source.read(_chunkSize);
        final box = await _aes.encrypt(
          chunk,
          secretKey: key,
          aad: [...header, ..._be32(index++)],
        );
        sink.add(_be32(box.cipherText.length));
        sink.add(box.nonce);
        sink.add(box.cipherText);
        sink.add(box.mac.bytes);
        if (chunk.isEmpty) break;
      }
    } finally {
      await source.close();
      await sink.close();
    }
  }

  Future<void> _decrypt(File input, File output, String password) async {
    final source = await input.open();
    final sink = output.openWrite();
    Future<List<int>> exact(int size) async {
      final bytes = await source.read(size);
      if (bytes.length != size) {
        throw const FormatException('Truncated backup file');
      }
      return bytes;
    }

    try {
      final magic = ascii.decode(await exact(8), allowInvalid: true);
      if (magic != _magic && magic != _legacyMagic) {
        throw const FormatException('Not a journal backup file');
      }
      final salt = await exact(16), iterationsBytes = await exact(4);
      final iterations = _read32(iterationsBytes);
      if (iterations < 10000 || iterations > 2000000) {
        throw const FormatException(
          'Unsupported backup key derivation settings',
        );
      }
      var header = <int>[];
      final key = await _key(password, salt, iterations);
      if (magic == _magic) {
        final kdf = await exact(1);
        if (kdf.single != 1) {
          throw const FormatException(
            'Unsupported backup key derivation algorithm',
          );
        }
        final verifier = await exact(16), expected = await _verifier(key);
        var diff = 0;
        for (var i = 0; i < 16; i++) {
          diff |= verifier[i] ^ expected[i];
        }
        if (diff != 0) throw const WrongPasswordException();
        header = [
          ...ascii.encode(magic),
          ...salt,
          ...iterationsBytes,
          ...kdf,
          ...verifier,
        ];
      }
      var index = 0, finished = false;
      while (true) {
        final lengthBytes = await source.read(4);
        if (lengthBytes.isEmpty) break;
        if (lengthBytes.length != 4) {
          throw const FormatException('Truncated backup file');
        }
        final length = _read32(lengthBytes);
        if (length > _chunkSize) {
          throw const FormatException('Corrupted backup chunk');
        }
        final nonce = await exact(12),
            cipher = await exact(length),
            tag = await exact(16);
        List<int> plain;
        try {
          plain = await _aes.decrypt(
            SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
            secretKey: key,
            aad: magic == _magic ? [...header, ..._be32(index)] : const [],
          );
        } on SecretBoxAuthenticationError {
          if (magic == _legacyMagic && index == 0) {
            throw const WrongPasswordException();
          }
          throw const FormatException(
            'Corrupted backup: authentication failed',
          );
        }
        index++;
        if (magic == _magic && length == 0) {
          finished = true;
          if (await source.position() != await source.length()) {
            throw const FormatException('Corrupted backup: trailing data');
          }
          break;
        }
        sink.add(plain);
      }
      if (magic == _magic && !finished || index == 0) {
        throw const FormatException('Truncated backup file');
      }
    } finally {
      await source.close();
      await sink.close();
    }
  }

  Future<void> _extract(File zip, Directory target) async {
    // Validate every path before letting the streaming extractor write it.
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final item in archive.files) {
        final normalized = item.name.replaceAll('\\', '/');
        if (p.posix.isAbsolute(normalized) ||
            normalized.split('/').contains('..') ||
            normalized.contains(':') ||
            item.isSymbolicLink) {
          throw const FormatException('Unsafe path in backup');
        }
        if (!(const [
              'manifest.json',
              'journals.json',
              'tags.json',
              'entries.ndjson',
            ].contains(normalized) ||
            normalized.startsWith('images/'))) {
          throw const FormatException('Unexpected file in backup');
        }
      }
    } finally {
      input.close();
    }
    await extractFileToDisk(zip.path, target.path);
  }

  Future<int> import(
    File backup,
    String password, {
    void Function(BackupProgress)? onProgress,
    DuplicatePolicy duplicates = DuplicatePolicy.skip,
  }) async {
    final work = await _work();
    final createdFiles = <String>[];
    try {
      onProgress?.call(const BackupProgress('Opening encrypted backup', .05));
      final zip = File(p.join(work.path, 'restore.zip'));
      await _decrypt(backup, zip, password);
      final extracted = Directory(p.join(work.path, 'contents'));
      await _extract(zip, extracted);
      final manifestFile = File(p.join(extracted.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw const FormatException('Not a backup file: manifest missing');
      }
      final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
      if (manifest['format'] != 'modern-journal-backup' ||
          ![1, 2].contains(manifest['version'])) {
        throw const FormatException('Unsupported journal backup format');
      }
      final journals =
          jsonDecode(
                await File(
                  p.join(extracted.path, 'journals.json'),
                ).readAsString(),
              )
              as List;
      final tags =
          jsonDecode(
                await File(p.join(extracted.path, 'tags.json')).readAsString(),
              )
              as List;
      final ndjson = File(p.join(extracted.path, 'entries.ndjson'));
      var actual = 0;
      // Validate the complete stream before changing any database rows.
      await for (final line
          in ndjson
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final e = jsonDecode(line) as Map;
        if (e['journalId'] is! int ||
            e['contentJson'] is! String ||
            jsonDecode(e['contentJson'] as String) is! List) {
          throw const FormatException('Corrupted backup entry');
        }
        DateTime.parse(e['entryDate'] as String);
        DateTime.parse(e['createdAt'] as String);
        DateTime.parse(e['updatedAt'] as String);
        for (final name in (e['attachments'] as List? ?? [])) {
          if (name is! String ||
              p.basename(name) != name ||
              name.contains('\\')) {
            throw const FormatException('Invalid attachment path');
          }
          if (!await File(p.join(extracted.path, 'images', name)).exists()) {
            throw const FormatException('Backup attachment is missing');
          }
        }
        actual++;
      }
      if (actual != manifest['entryCount']) {
        throw const FormatException(
          'Truncated backup: entry count does not match',
        );
      }
      onProgress?.call(const BackupProgress('Restoring writing', .4));
      var imported = 0, processed = 0;
      await db.transaction(() async {
        final journalMap = <int, int>{}, tagMap = <int, int>{};
        for (final raw in journals) {
          final j = raw as Map;
          final existing =
              await (db.select(db.journals)
                    ..where((t) => t.name.equals(j['name'] as String)))
                  .getSingleOrNull();
          final id =
              existing?.id ??
              await db.createJournal(
                j['name'] as String,
                j['color'] as int,
                j['emoji'] as String,
              );
          if (existing == null) {
            await (db.update(db.journals)..where((t) => t.id.equals(id))).write(
              JournalsCompanion(
                archived: Value(j['archived'] as bool? ?? false),
                sortOrder: Value(j['sortOrder'] as int? ?? 0),
                deletedAt: Value(
                  j['deletedAt'] == null
                      ? null
                      : DateTime.parse(j['deletedAt'] as String),
                ),
              ),
            );
          }
          journalMap[j['id'] as int] = id;
        }
        for (final t in tags) {
          tagMap[t['id'] as int] = await db.ensureTag(t['name'] as String);
        }
        await for (final line
            in ndjson
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.trim().isEmpty) continue;
          final e = jsonDecode(line) as Map;
          final stableId =
              e['stableId'] as String? ??
              const Uuid().v5(
                Namespace.url.value,
                '${e['createdAt']}|${e['entryDate']}|${e['contentJson']}',
              );
          final existing = await (db.select(
            db.entries,
          )..where((t) => t.stableId.equals(stableId))).getSingleOrNull();
          processed++;
          if (existing != null && duplicates == DuplicatePolicy.skip) continue;
          final journalId = journalMap[e['journalId'] as int];
          if (journalId == null) {
            throw const FormatException(
              'Backup references an unknown notebook',
            );
          }
          final plain = e['plainText'] as String? ?? '';
          final value = EntriesCompanion(
            journalId: Value(journalId),
            stableId: Value(stableId),
            title: Value(e['title'] as String? ?? ''),
            contentJson: Value(e['contentJson'] as String),
            plainText: Value(plain),
            entryDate: Value(DateTime.parse(e['entryDate'] as String)),
            createdAt: Value(DateTime.parse(e['createdAt'] as String)),
            updatedAt: Value(DateTime.parse(e['updatedAt'] as String)),
            wordCount: Value(countWords(plain)),
            writingSeconds: Value(e['writingSeconds'] as int? ?? 0),
            mood: Value(e['mood'] as int?),
            isDraft: Value(e['isDraft'] as bool? ?? false),
            location: Value(e['location'] as String?),
            deletedAt: Value(
              e['deletedAt'] == null
                  ? null
                  : DateTime.parse(e['deletedAt'] as String),
            ),
          );
          final int id;
          if (existing == null) {
            id = await db.insertEntry(value);
          } else {
            id = existing.id;
            await db.updateEntry(id, value);
            await (db.delete(
              db.attachments,
            )..where((a) => a.entryId.equals(id))).go();
          }
          await db.setEntryTags(
            id,
            (e['tagIds'] as List? ?? [])
                .map((t) => tagMap[t])
                .whereType<int>()
                .toList(),
          );
          for (final name in (e['attachments'] as List? ?? [])) {
            final newName = await attachmentService.storeFile(
              p.join(extracted.path, 'images', name as String),
            );
            createdFiles.add(newName);
            await db.addAttachment(id, newName);
          }
          imported++;
          onProgress?.call(
            BackupProgress(
              'Restored $imported entries',
              .4 + .6 * processed / (actual == 0 ? 1 : actual),
            ),
          );
        }
      });
      onProgress?.call(const BackupProgress('Restore complete', 1));
      return imported;
    } catch (_) {
      for (final name in createdFiles) {
        await attachmentService.deleteFile(name);
      }
      rethrow;
    } finally {
      await work.delete(recursive: true);
    }
  }

  static Uint8List _be32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value);
  static int _read32(List<int> bytes) =>
      Uint8List.fromList(bytes).buffer.asByteData().getUint32(0);
}

class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'Wrong backup password';
}
