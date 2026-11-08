import '../api/gen/wambito_api.dart';
import '../capture/parser/dates.dart';

enum DayWhen { today, yesterday, upcoming, past }

/// One day of transactions, as the movements list shows it.
class DayGroup {
  const DayGroup({
    required this.date,
    required this.when,
    required this.total,
    required this.items,
  });

  /// `YYYY-MM-DD`.
  final String date;
  final DayWhen when;

  /// The day's signed total, in cents.
  final int total;

  /// In the API's order (newest first).
  final List<Transaction> items;
}

DayWhen _whenOf(String date, String today, String yesterday) => date == today
    ? DayWhen.today
    : date.compareTo(today) > 0
    ? DayWhen.upcoming
    : date == yesterday
    ? DayWhen.yesterday
    : DayWhen.past;

/// A month's transactions by day, as home lists them: today on top, then the days gone by (newest
/// first), then the days still to come at the bottom (the nearest first, where the pending ones
/// are). The web's `groupByDay` (apps/web/app/features/home/home-model.ts).
List<DayGroup> groupByDay(List<Transaction> items, String today) {
  final byDate = <String, List<Transaction>>{};
  for (final tx in items) {
    byDate.putIfAbsent(tx.date, () => []).add(tx);
  }
  final yesterday = addDays(today, -1);
  final groups = [
    for (final MapEntry(key: date, value: list) in byDate.entries)
      DayGroup(
        date: date,
        when: _whenOf(date, today, yesterday),
        total: list.fold(0, (sum, tx) => sum + tx.amount),
        items: list,
      ),
  ];
  int rank(DayGroup g) => g.when == DayWhen.today
      ? 0
      : g.when == DayWhen.upcoming
      ? 2
      : 1;
  groups.sort((a, b) {
    if (rank(a) != rank(b)) return rank(a) - rank(b);
    // Upcoming: nearest first. Everything else: newest first.
    return a.when == DayWhen.upcoming ? a.date.compareTo(b.date) : b.date.compareTo(a.date);
  });
  return groups;
}

/// Transactions by day in the API's order (newest first), as a search lists them: a future pending
/// day stays above older days when it is newer, nothing moves to the bottom. The web's
/// `groupNewestFirst` (apps/web/app/features/home/home-model.ts).
List<DayGroup> groupNewestFirst(List<Transaction> items, String today) {
  final yesterday = addDays(today, -1);
  final days = <(String, List<Transaction>)>[];
  for (final tx in items) {
    if (days.isNotEmpty && days.last.$1 == tx.date) {
      days.last.$2.add(tx);
    } else {
      days.add((tx.date, [tx]));
    }
  }
  return [
    for (final (date, list) in days)
      DayGroup(
        date: date,
        when: _whenOf(date, today, yesterday),
        total: list.fold(0, (sum, tx) => sum + tx.amount),
        items: list,
      ),
  ];
}
