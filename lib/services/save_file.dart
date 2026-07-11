import 'package:flutter/services.dart';

/// Bridges to MainActivity's SAF ACTION_CREATE_DOCUMENT handler.
/// Returns true if saved, false if the user cancelled the picker.
Future<bool> saveFileToDevice(String sourcePath, String fileName) async {
  const channel = MethodChannel('journal/save_file');
  final saved = await channel.invokeMethod<bool>('saveFile', {
    'sourcePath': sourcePath,
    'fileName': fileName,
  });
  return saved ?? false;
}
