import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Owns the `attachments/` folder inside the app documents directory.
/// The database only stores file names relative to that folder.
class AttachmentService {
  Directory? _dir;

  Future<Directory> attachmentsDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'attachments'));
    await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<File> fileFor(String fileName) async =>
      File(p.join((await attachmentsDir()).path, fileName));

  /// Opens the system picker / camera and copies the image into the
  /// attachments folder. Returns the stored file name, or null if cancelled.
  Future<String?> pickImage({required bool fromCamera}) async {
    final picked = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (picked == null) return null;
    final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
    final name = '${const Uuid().v4()}$ext';
    final target = await fileFor(name);
    await File(picked.path).copy(target.path);
    return name;
  }

  Future<void> deleteFile(String fileName) async {
    final f = await fileFor(fileName);
    if (await f.exists()) await f.delete();
  }
}
