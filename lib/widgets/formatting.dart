import 'package:intl/intl.dart';

import '../data/database.dart';

/// Every number the app prints goes through here, so "18 min" never appears as
/// "18m" on one screen and "0h 18m" on another.

/// Minutes at the page, for a feed row or a day header: `4 min`, `1 h 12 min`.
/// Under a minute is not worth a line of its own and reads as `<1 min`.
String formatWritingTime(int seconds) {
  if (seconds <= 0) return '';
  if (seconds < 60) return '<1 min';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60, rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// The long form used in statistics, where the total is the point.
String formatTotalTime(int seconds) {
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60, rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// `1 word`, not `1 words`.
String formatWords(int words) => words == 1 ? '1 word' : '${formatNumber(words)} words';

/// Thousands are separated with a thin space, not a comma.
///
/// Every number in the app is set with tabular figures so counts do not jitter
/// as they tick over, and a tabular comma is as wide as a digit — "1,092"
/// rendered as "1 , 092", which looks like a mistake. A thin space is the SI
/// convention and sits correctly on a tabular grid.
String formatNumber(int n) => NumberFormat.decimalPattern()
    .format(n)
    .replaceAll(',', ' ')
    .replaceAll('.', ' ');

String formatCount(int n, String one, String many) =>
    n == 1 ? '1 $one' : '${formatNumber(n)} $many';

/// A run of days with nothing in it, said the way a person would.
String formatGap(int days) {
  if (days < 31) return 'nothing for $days days';
  final months = (days / 30.44).round();
  if (months < 12) return 'nothing for $months months';
  final years = (days / 365.25).round();
  return years == 1 ? 'nothing for a year' : 'nothing for $years years';
}

/// How much later an entry was written than the day it is filed under — the
/// one fact this app has and a cloud diary does not.
///
/// Counted with [dayOrdinal], never `Duration.inDays`: a DST changeover makes a
/// calendar day 23 hours long and `inDays` would report it as zero.
String? formatBackfill(DateTime entryDay, DateTime writtenDay) {
  final days = dayOrdinal(writtenDay) - dayOrdinal(entryDay);
  if (days < 1) return null;
  if (days == 1) return 'written a day later';
  if (days < 31) return 'written $days days later';
  final months = (days / 30.44).round();
  if (months < 12) return 'written $months months later';
  return 'written years later';
}
