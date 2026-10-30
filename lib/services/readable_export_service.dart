import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/database.dart';
import 'attachment_service.dart';

class ReadableExportService {
  ReadableExportService(this.db, this.attachments);
  final AppDatabase db;
  final AttachmentService attachments;
  Stream<Entry> _entries() async* {
    var cursor = 0;
    while (true) {
      final page =
          await (db.select(db.entries)
                ..where(
                  (e) => e.id.isBiggerThanValue(cursor) & e.deletedAt.isNull(),
                )
                ..orderBy([(e) => OrderingTerm.asc(e.id)])
                ..limit(200))
              .get();
      if (page.isEmpty) break;
      for (final entry in page) {
        yield entry;
      }
      cursor = page.last.id;
    }
  }

  Future<File> markdown() async {
    final temp = await getTemporaryDirectory();
    final file = File(
      p.join(temp.path, 'journal-${DateTime.now().millisecondsSinceEpoch}.md'),
    );
    final sink = file.openWrite();
    final images = <String>{};
    final deletedJournals = (await (db.select(
      db.journals,
    )..where((j) => j.deletedAt.isNotNull())).get()).map((j) => j.id).toSet();
    try {
      sink.writeln('# My journal\n');
      await for (final entry in _entries()) {
        if (deletedJournals.contains(entry.journalId)) continue;
        final tags = await db.tagsForEntry(entry.id);
        sink.writeln(
          '## ${entry.title.isEmpty ? DateFormat.yMMMMd().format(entry.entryDate) : entry.title}\n',
        );
        sink.writeln(
          'Filed under ${DateFormat.yMMMMd().format(entry.entryDate)} · written ${DateFormat.yMMMMd().format(entry.createdAt)}\n',
        );
        if (entry.location != null) {
          sink.writeln('Location: ${entry.location}\n');
        }
        sink.writeln('${entry.plainText}\n');
        if (tags.isNotEmpty) {
          sink.writeln('${tags.map((t) => '#${t.name}').join(' ')}\n');
        }
        for (final attachment in await db.attachmentsForEntry(entry.id)) {
          images.add(attachment.fileName);
          final isVoice = attachment.fileName.endsWith('.m4a');
          sink.writeln(
            '${isVoice ? '' : '!'}[${isVoice ? 'Voice note' : 'Photo'}](attachments/${attachment.fileName})\n',
          );
        }
        sink.writeln('---\n');
      }
    } finally {
      await sink.close();
    }
    if (images.isEmpty) return file;
    final output = File('${file.path}.zip');
    final zip = ZipFileEncoder()..create(output.path);
    try {
      await zip.addFile(file, 'journal.md');
      for (final name in images) {
        final image = await attachments.fileFor(name);
        if (await image.exists()) await zip.addFile(image, 'attachments/$name');
      }
    } finally {
      await zip.close();
      await file.delete();
    }
    return output;
  }

  Future<File> pdf() async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Literata-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Literata-Bold.ttf'),
    );
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final deletedJournals = (await (db.select(
      db.journals,
    )..where((j) => j.deletedAt.isNotNull())).get()).map((j) => j.id).toSet();
    await for (final entry in _entries()) {
      if (deletedJournals.contains(entry.journalId)) continue;
      final parts = <pw.Widget>[
        pw.Header(
          level: 0,
          text: entry.title.isEmpty ? 'Untitled entry' : entry.title,
        ),
        pw.Paragraph(
          text:
              'Filed under ${DateFormat.yMMMMd().format(entry.entryDate)} · Written ${DateFormat.yMMMMd().format(entry.createdAt)}',
        ),
        if (entry.location != null)
          pw.Paragraph(text: 'Location: ${entry.location}'),
      ];
      // Keep blocks short enough for any page size while MultiPage flows them.
      for (var i = 0; i < entry.plainText.length; i += 800) {
        parts.add(
          pw.Paragraph(
            text: entry.plainText.substring(
              i,
              (i + 800).clamp(0, entry.plainText.length),
            ),
          ),
        );
      }
      for (final attachment in await db.attachmentsForEntry(entry.id)) {
        final file = await attachments.fileFor(attachment.fileName);
        if (!attachment.fileName.endsWith('.m4a') && await file.exists()) {
          parts.add(
            pw.Image(
              pw.MemoryImage(await file.readAsBytes()),
              height: 240,
              fit: pw.BoxFit.contain,
            ),
          );
        }
      }
      doc.addPage(
        pw.MultiPage(
          maxPages: 10000,
          build: (_) => parts,
          footer: (context) => pw.Text(
            '${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
      );
    }
    if (doc.document.pdfPageList.pages.isEmpty) {
      doc.addPage(pw.Page(build: (_) => pw.Text('My journal')));
    }
    final temp = await getTemporaryDirectory();
    return File(
      p.join(temp.path, 'journal-${DateTime.now().millisecondsSinceEpoch}.pdf'),
    ).writeAsBytes(await doc.save());
  }
}
