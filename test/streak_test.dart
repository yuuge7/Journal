import 'package:flutter_test/flutter_test.dart';
import 'package:journal/data/database.dart';

/// [computeStreaks] is pure, so these run without a database.
void main() {
  final now = DateTime(2026, 8, 24, 15, 0);
  DateTime day(int d, [int hour = 12]) => DateTime(2026, 8, d, hour);

  group('computeStreaks', () {
    test('no entries', () {
      final s = computeStreaks(const [], now: now);
      expect(s.current, 0);
      expect(s.longest, 0);
    });

    test('written today', () {
      final s = computeStreaks([day(24)], now: now);
      expect(s.current, 1);
      expect(s.longest, 1);
    });

    test('consecutive days ending today', () {
      final s = computeStreaks([day(22), day(23), day(24)], now: now);
      expect(s.current, 3);
      expect(s.longest, 3);
    });

    test('several entries on the same day count once', () {
      final s = computeStreaks([day(24, 1), day(24, 9), day(24, 23)], now: now);
      expect(s.current, 1);
      expect(s.longest, 1);
    });

    test('an entry just before midnight still belongs to its own day', () {
      final s = computeStreaks([day(23, 23), day(24, 0)], now: now);
      expect(s.current, 2);
    });

    test('streak survives if the last entry was yesterday', () {
      final s = computeStreaks([day(22), day(23)], now: now);
      expect(s.current, 2);
    });

    test('streak is broken once two days are missed', () {
      final s = computeStreaks([day(21), day(22)], now: now);
      expect(s.current, 0);
      expect(s.longest, 2);
    });

    test('longest keeps the best historical run', () {
      final s = computeStreaks(
          [day(10), day(11), day(12), day(13), day(20), day(24)],
          now: now);
      expect(s.current, 1);
      expect(s.longest, 4);
    });

    test('unordered input', () {
      final s = computeStreaks([day(24), day(22), day(23)], now: now);
      expect(s.current, 3);
      expect(s.longest, 3);
    });

    test('a future-dated entry neither starts nor extends the streak', () {
      final s = computeStreaks([day(24), day(30)], now: now);
      expect(s.current, 1);
    });

    test('only future entries means no current streak', () {
      final s = computeStreaks([day(30), day(31)], now: now);
      expect(s.current, 0);
    });

    test('consecutive days across a DST switch stay consecutive', () {
      // Europe/Bucharest springs forward on 2026-03-29: that calendar day is
      // 23 hours long, which `Duration.inDays` reports as 0 days.
      final march = [
        DateTime(2026, 3, 28, 12),
        DateTime(2026, 3, 29, 12),
        DateTime(2026, 3, 30, 12),
      ];
      final s = computeStreaks(march, now: DateTime(2026, 3, 30, 20));
      expect(s.current, 3);
      expect(s.longest, 3);
    });

    test('dayOrdinal is stable across a DST switch', () {
      expect(
          dayOrdinal(DateTime(2026, 3, 29)) - dayOrdinal(DateTime(2026, 3, 28)),
          1);
      expect(
          dayOrdinal(DateTime(2026, 10, 25)) -
              dayOrdinal(DateTime(2026, 10, 24)),
          1);
    });
  });
}
