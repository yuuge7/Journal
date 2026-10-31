import 'package:flutter/services.dart';

/// Small Android features stay local and use no network permission.
class PlatformService {
  static const channel = MethodChannel('journal/platform');
  static Future<T?> call<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> secure(bool enabled) =>
      call<void>('secure', {'enabled': enabled});
  static bool _authenticating = false;
  static bool get authenticating => _authenticating;

  /// Android verifies the device credential; Journal never sees the PIN.
  static Future<bool> authenticate({bool deviceCredentialOnly = false}) async {
    if (_authenticating) return false;
    _authenticating = true;
    try {
      return await call<bool>('authenticate', {
            'deviceCredentialOnly': deviceCredentialOnly,
          }) ??
          false;
    } finally {
      _authenticating = false;
    }
  }

  static Future<String?> location() => call<String>('location');
  static Future<String?> startRecording() => call<String>('startRecording');
  static Future<String?> stopRecording() => call<String>('stopRecording');
  static Future<void> play(String path) => call<void>('play', {'path': path});
  static Future<void> reminders(int days) =>
      call<void>('reminders', {'days': days});
  static Future<void> widget({required int streak, required bool written}) =>
      call<void>('widget', {'streak': streak, 'written': written});
}
