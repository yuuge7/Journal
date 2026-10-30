import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/theme/app_theme.dart';
import 'package:journal/theme/tokens.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('all reading roles meet AA on $brightness ground and page', () {
      final t = buildTheme(brightness: brightness).extension<JournalTokens>()!;
      for (final fg in [t.ink, t.inkDim, t.inkFaint, t.accent, t.danger]) {
        for (final bg in [t.ground, t.page]) {
          final a = fg.computeLuminance(), b = bg.computeLuminance();
          final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$fg on $bg in $brightness',
          );
        }
      }
    });
  }
}
