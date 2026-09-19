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

  test('writing before the day-ends-at hour still belongs to the day before',
      () {
    final day = DateTime(2026, 9, 3);
    // Midnight cut-off: 00:30 the next morning is already a day later.
    expect(formatBackfill(day, DateTime(2026, 9, 4, 0, 30)),
        'written a day later');
    // Day ends at 04:00: up to 03:59 is still the 3rd.
    expect(formatBackfill(day, DateTime(2026, 9, 4, 2), dayEndsAt: 4), isNull);
    expect(formatBackfill(day, DateTime(2026, 9, 4, 3, 59), dayEndsAt: 4),
        isNull);
    expect(formatBackfill(day, DateTime(2026, 9, 4, 4), dayEndsAt: 4),
        'written a day later');
    // Two nights on, before the cut-off, is one day later — not two.
    expect(formatBackfill(day, DateTime(2026, 9, 5, 1), dayEndsAt: 4),
        'written a day later');
    // Writing the same evening is never "later", cut-off or not.
    expect(formatBackfill(day, DateTime(2026, 9, 3, 22), dayEndsAt: 4), isNull);
    // Filing an entry under tomorrow at 1 am does not turn into "later" either.
    expect(formatBackfill(DateTime(2026, 9, 4), DateTime(2026, 9, 4, 1),
        dayEndsAt: 4), isNull);
  });
}
