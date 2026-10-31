import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:journal/data/database.dart';
import 'package:journal/main.dart';
import 'package:journal/providers.dart';
import 'package:journal/services/attachment_service.dart';
import 'package:journal/services/platform_service.dart';

/// Optional device-PIN test. Run only on a test emulator with a known PIN and
/// --dart-define=TEST_DEVICE_PIN=true. Enter that PIN in Android's prompt while
/// the test waits. No PIN or biometric secret is stored in Journal.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'local GPS and device-PIN app lock',
    (tester) async {
      final db = AppDatabase.withExecutor(NativeDatabase.memory());
      final temp = await getTemporaryDirectory();
      final dir = await Directory(
        '${temp.path}/platform-test-attachments',
      ).create(recursive: true);
      await db.setSetting('app_lock', 'true');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            attachmentServiceProvider.overrideWithValue(
              AttachmentService(directory: dir),
            ),
          ],
          child: const JournalApp(),
        ),
      );
      for (
        var i = 0;
        i < 120 && find.text('Unlock Journal').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Unlock Journal'), findsOneWidget);
      debugPrint('READY_FOR_DEVICE_PIN');
      await tester.tap(find.text('Use device PIN'));
      for (var i = 0; i < 240; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text('Unlock Journal').evaluate().isEmpty) break;
      }
      expect(find.text('Unlock Journal'), findsNothing);
      expect(find.text('Nothing written yet'), findsOneWidget);
      debugPrint('READY_FOR_GPS_FIX');
      final location = await PlatformService.location();
      expect(location, matches(RegExp(r'^-?\d+\.\d+, -?\d+\.\d+$')));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Unlock Journal'), findsOneWidget);
      expect(find.text('Nothing written yet'), findsNothing);
      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    skip: !const bool.fromEnvironment('TEST_DEVICE_PIN'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
