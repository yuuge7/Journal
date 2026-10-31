import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';
import 'package:journal/main.dart';
import 'package:journal/providers.dart';
import 'package:journal/screens/settings_screen.dart';
import 'package:journal/services/attachment_service.dart';
import 'package:journal/services/platform_service.dart';
import 'package:journal/theme/app_theme.dart';

class _NoAttachments extends AttachmentService {
  @override
  Future<void> sweep(Set<String> referenced) async {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late List<MethodCall> authenticationCalls;
  late Future<bool> Function() authenticate;

  setUp(() {
    authenticationCalls = [];
    authenticate = () async => true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PlatformService.channel,
      (call) async {
        if (call.method == 'authenticate') {
          authenticationCalls.add(call);
          return authenticate();
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PlatformService.channel,
      null,
    );
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(400, 850),
  }) async {
    // Exercise the Android app in a portrait phone viewport.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    await db.setSetting('app_lock', 'true');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          attachmentServiceProvider.overrideWithValue(_NoAttachments()),
        ],
        child: const JournalApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your private notebook'), findsOneWidget);
    expect(find.text('Nothing written yet'), findsNothing);
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final closing = db.close();
    // Disposing routes cancels query streams on a later event-loop turn.
    // Keep fake time moving until Drift has drained those cancellations.
    var closed = false;
    closing.then((_) => closed = true);
    for (var i = 0; i < 20 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await closing;
  }

  void background() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  for (final devicePin in [false, true]) {
    testWidgets('${devicePin ? 'PIN' : 'biometric'} unlock and relock', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(
        find.text(devicePin ? 'Use device PIN' : 'Unlock Journal'),
      );
      await tester.pumpAndSettle();
      expect(authenticationCalls.single.arguments, {
        'deviceCredentialOnly': devicePin,
      });
      expect(find.text('Your private notebook'), findsNothing);
      expect(find.text('Nothing written yet'), findsOneWidget);

      // The first background event must lock, without a settings screen visit.
      background();
      await tester.pumpAndSettle();
      expect(find.text('Your private notebook'), findsOneWidget);
      expect(find.text('Nothing written yet'), findsNothing);
      await disposeApp(tester);
    });
  }

  testWidgets('cancelled biometrics leaves PIN available', (tester) async {
    authenticate = () async => false;
    await pumpApp(tester);
    await tester.tap(find.text('Unlock Journal'));
    await tester.pumpAndSettle();
    expect(find.text('Your private notebook'), findsOneWidget);
    expect(find.text('Nothing written yet'), findsNothing);

    authenticate = () async => true;
    await tester.tap(find.text('Use device PIN'));
    await tester.pumpAndSettle();
    expect(authenticationCalls.last.arguments, {'deviceCredentialOnly': true});
    expect(find.text('Nothing written yet'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('cancelled PIN stays locked and allows another attempt', (
    tester,
  ) async {
    authenticate = () async => false;
    await pumpApp(tester);
    await tester.tap(find.text('Use device PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing written yet'), findsNothing);
    expect(find.text('Your private notebook'), findsOneWidget);

    authenticate = () async => true;
    await tester.tap(find.text('Use device PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing written yet'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('only one unlock prompt can be open', (tester) async {
    final pending = Completer<bool>();
    authenticate = () => pending.future;
    await pumpApp(tester);
    await tester.tap(find.text('Use device PIN'));
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Unlock Journal'));
    expect(authenticationCalls, hasLength(1));
    // Android's credential activity can pause Flutter while it verifies PIN.
    background();
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Nothing written yet'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('native errors stay locked and display a readable message', (
    tester,
  ) async {
    authenticate = () async => throw PlatformException(
      code: 'NO_LOCK',
      message:
          'Set a device PIN, pattern or password in Android settings first.',
    );
    await pumpApp(tester);
    await tester.tap(find.text('Use device PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing written yet'), findsNothing);
    expect(
      find.text(
        'Set a device PIN, pattern or password in Android settings first.',
      ),
      findsOneWidget,
    );
    authenticate = () async => true;
    await tester.tap(find.text('Unlock Journal'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing written yet'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('disposal while Android verifies PIN is safe', (tester) async {
    final pending = Completer<bool>();
    authenticate = () => pending.future;
    await pumpApp(tester);
    await tester.tap(find.text('Use device PIN'));
    await tester.pump();
    await disposeApp(tester);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(PlatformService.authenticating, isFalse);
  });

  for (final allowed in [false, true]) {
    testWidgets('Settings changes app lock only after PIN success: $allowed', (
      tester,
    ) async {
      db = AppDatabase.withExecutor(NativeDatabase.memory());
      authenticate = () async => allowed;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: buildTheme(brightness: Brightness.light),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();
      expect(authenticationCalls.single.arguments, {
        'deviceCredentialOnly': true,
      });
      expect(await db.setting('app_lock'), allowed ? 'true' : isNull);
      await disposeApp(tester);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('lock actions fit a small screen with 2x text: $brightness', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, size: const Size(320, 480));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Use device PIN'));
      await tester.tap(find.text('Use device PIN'));
      await tester.pumpAndSettle();
      expect(authenticationCalls.single.arguments, {
        'deviceCredentialOnly': true,
      });
      expect(find.text('Your private notebook'), findsNothing);
      await disposeApp(tester);
    });
  }

  testWidgets('Settings PIN activity does not leave a lock over Settings', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Unlock Journal'));
    await tester.pumpAndSettle();
    // Push through the app navigator so the real lock overlay stays present.
    final context = tester.element(find.text('Nothing written yet'));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await tester.pumpAndSettle();
    final pending = Completer<bool>();
    authenticate = () => pending.future;
    await tester.tap(find.text('App lock'));
    await tester.pump();
    background();
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(await db.setting('app_lock'), 'false');
    expect(find.text('Your private notebook'), findsNothing);
    expect(find.text('App lock'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('backgrounding a cancelled Settings PIN prompt relocks Journal', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Unlock Journal'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Nothing written yet'));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await tester.pumpAndSettle();
    final pending = Completer<bool>();
    authenticate = () => pending.future;
    await tester.tap(find.text('App lock'));
    await tester.pump();
    background();
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(await db.setting('app_lock'), 'true');
    expect(find.text('Your private notebook'), findsOneWidget);
    expect(find.text('App lock'), findsNothing);
    await disposeApp(tester);
  });

  test(
    'platform authentication guard also covers non-lock-screen callers',
    () async {
      final pending = Completer<bool>();
      authenticate = () => pending.future;
      final first = PlatformService.authenticate(deviceCredentialOnly: true);
      expect(PlatformService.authenticating, isTrue);
      expect(await PlatformService.authenticate(), isFalse);
      expect(authenticationCalls, hasLength(1));
      pending.complete(false);
      expect(await first, isFalse);
      expect(PlatformService.authenticating, isFalse);
    },
  );
}
