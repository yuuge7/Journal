import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';
import 'generated_migrations/schema.dart';

void main() {
  test(
    'v3 snapshot migrates to v4 with text, dates, tags and attachments intact',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final old = await verifier.schemaAt(3);
      final day = DateTime(2025, 10, 30, 0, 15).millisecondsSinceEpoch ~/ 1000;
      old.rawDatabase.execute(
        "INSERT INTO journals(id,name,color,emoji) VALUES(7,'Private',1,'J')",
      );
      old.rawDatabase.execute(
        "INSERT INTO entries(id,journal_id,content_json,plain_text,entry_date,word_count,writing_seconds) VALUES(9,7,'[]','An old memory',?,3,600)",
        [day],
      );
      old.rawDatabase.execute("INSERT INTO tags(id,name) VALUES(2,'memory')");
      old.rawDatabase.execute(
        'INSERT INTO entry_tags(entry_id,tag_id) VALUES(9,2)',
      );
      old.rawDatabase.execute(
        "INSERT INTO attachments(entry_id,file_name) VALUES(9,'photo.jpg')",
      );
      final db = AppDatabase.withExecutor(old.newConnection());
      try {
        await verifier.migrateAndValidate(db, 4);
        final entry = (await db.getEntry(9))!;
        expect(entry.stableId, isNotEmpty);
        expect(entry.monthDay, '10-30');
        expect(entry.entryDate, DateTime(2025, 10, 30, 0, 15));
        expect(entry.writingSeconds, 600);
        expect((await db.tagsForEntry(9)).single.name, 'memory');
        expect((await db.attachmentsForEntry(9)).single.fileName, 'photo.jpg');
        expect((await db.watchFeed(search: 'memory').first).single.id, 9);
      } finally {
        await db.close();
      }
    },
  );
}
