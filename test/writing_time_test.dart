import 'package:flutter_test/flutter_test.dart';
import 'package:journal/widgets/formatting.dart';

void main() {
  test('minutes at the page, as a feed row states them', () {
    // Zero prints nothing: a row should not carry an empty measurement.
    expect(formatWritingTime(0), '');
    expect(formatWritingTime(45), '<1 min');
    expect(formatWritingTime(60), '1 min');
    expect(formatWritingTime(12 * 60 + 30), '12 min');
    expect(formatWritingTime(3600), '1 h');
    expect(formatWritingTime(2 * 3600 + 5 * 60), '2 h 5 min');
  });

  test('word counts are singular at one and grouped above a thousand', () {
    expect(formatWords(0), '0 words');
    expect(formatWords(1), '1 word');
    expect(formatWords(2), '2 words');
    expect(formatWords(1200), contains('200'));
  });

  test('a gap is spelled out in the largest unit that still reads plainly', () {
    expect(formatGap(2), 'nothing for 2 days');
    expect(formatGap(30), 'nothing for 30 days');
    expect(formatGap(60), 'nothing for 2 months');
    expect(formatGap(365), 'nothing for a year');
  });

  test('backfill only reports days the entry was written after the fact', () {
    expect(formatBackfill(DateTime(2026, 9, 3), DateTime(2026, 9, 3, 23)), isNull);
    expect(formatBackfill(DateTime(2026, 9, 3), DateTime(2026, 9, 4)),
        'written a day later');
    expect(formatBackfill(DateTime(2026, 9, 1), DateTime(2026, 9, 6)),
        'written 5 days later');
  });
}
