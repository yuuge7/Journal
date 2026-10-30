import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:journal/data/database.dart';
import 'package:journal/providers.dart';
import 'package:journal/screens/feed_screen.dart';
import 'package:journal/screens/calendar_screen.dart';
import 'package:journal/screens/stats_screen.dart';
import 'package:journal/screens/settings_screen.dart';
import 'package:journal/screens/journals_screen.dart';
import 'package:journal/screens/editor_screen.dart';
import 'package:journal/theme/app_theme.dart';
import 'package:journal/widgets/year_grid.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'all screens and editor work on a 320dp Android display with 2x text',
    (tester) async {
      final db = AppDatabase.withExecutor(NativeDatabase.memory());
      final journal = (await db.select(db.journals).get()).first.id;
      final id = await db.insertEntry(
        EntriesCompanion.insert(
          journalId: journal,
          contentJson: '[{"insert":"A page written on the emulator.\\n"}]',
          plainText: const Value('A page written on the emulator.'),
          title: const Value('A quiet afternoon'),
          entryDate: DateTime.now(),
          wordCount: const Value(6),
          writingSeconds: const Value(600),
          mood: const Value(4),
        ),
      );
      final temp = await getTemporaryDirectory();
      for (final brightness in Brightness.values) {
        for (final screen in <String, Widget>{
          'feed': const FeedScreen(),
          'calendar': const CalendarScreen(),
          'stats': const StatsScreen(),
          'settings': const SettingsScreen(),
          'journals': const JournalsScreen(),
          'year': const Scaffold(body: YearGrid()),
          'editor': EditorScreen(entryId: id),
        }.entries) {
          debugPrint('Large text ${brightness.name} ${screen.key}');
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('qa-root'),
              child: ProviderScope(
                overrides: [databaseProvider.overrideWithValue(db)],
                child: MaterialApp(
                  theme: buildTheme(brightness: brightness),
                  debugShowCheckedModeBanner: false,
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                    FlutterQuillLocalizations.delegate,
                  ],
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: true,
                    ),
                    child: child!,
                  ),
                  home: screen.value,
                ),
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('qa-root')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${temp.path}/qa-large-${brightness.name}-${screen.key}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          binding.reportData ??= {};
          (binding.reportData!.putIfAbsent('screenshots', () => <dynamic>[])
                  as List)
              .add({
                'screenshotName': 'large-${brightness.name}-${screen.key}',
                'bytes': data.buffer.asUint8List().toList(),
              });
          image.dispose();
          if (screen.key == 'editor') {
            await tester.tap(find.byType(QuillEditor));
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull);
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pump(const Duration(milliseconds: 500));
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await db.close();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
