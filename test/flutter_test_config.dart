import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.textScaleFactorTestValue = double.parse(
    const String.fromEnvironment('TEST_TEXT_SCALE', defaultValue: '1'),
  );
  await testMain();
}
