import '../core/dates.dart' show monthOf, todayIn;
import '../core/js_math.dart' show stableSorted;
import '../local/backend.dart';

/// One day of the due list: the recurring payments pending on [date] (`YYYY-MM-DD`, in the
/// profile's zone), in the order they were created.
class DueDay {
  const DueDay(this.date, this.names);

  final String date;
  final List<String> names;

  Map<String, Object?> toJson() => {'date': date, 'names': names};
}

/// The recurring payments still pending in the [days] days from [today] (inclusive), read from the
/// vault in [backend]: what "Hoy vence…" says on each of them. Nothing is asked of the server
/// (a `preview` account's payments live only on the phone).
///
/// Asks `GET /v1/transactions?status=pending&month=<m>` for each month the window touches (which
/// also makes the month's occurrences), keeps the rows with a `recurrenceId` and a date inside the
/// window, and groups their names by date, oldest creation first. Days with nothing are absent.
Future<List<DueDay>> dueDays(LocalBackend backend, {required String today, int days = 14}) async {
  final start = DateTime.parse('${today}T00:00:00Z');
  final last = _date(start.add(Duration(days: days - 1)));
  final months = <String>[];
  for (var d = start; _date(d).compareTo(last) <= 0; d = d.add(const Duration(days: 1))) {
    final m = monthOf(_date(d));
    if (months.isEmpty || months.last != m) months.add(m);
  }
  final rows = <(String date, String created, String name)>[];
  for (final month in months) {
    String? cursor;
    do {
      final answer = await backend.handle('GET', '/v1/transactions', {
        'status': 'pending',
        'month': month,
        'limit': '200',
        'cursor': ?cursor,
      }, null);
      final body = answer?.body;
      if (answer == null || answer.status != 200 || body is! Map) break;
      for (final item in (body['items'] as List? ?? const [])) {
        if (item is! Map || item['recurrenceId'] == null) continue;
        final date = item['date'];
        final name = item['name'];
        if (date is! String || name is! String) continue;
        if (date.compareTo(today) < 0 || date.compareTo(last) > 0) continue;
        rows.add((date, item['createdAt'] as String? ?? '', name));
      }
      cursor = body['nextCursor'] as String?;
    } while (cursor != null);
  }
  final sorted = stableSorted(rows, (a, b) {
    final byDate = a.$1.compareTo(b.$1);
    return byDate != 0 ? byDate : a.$2.compareTo(b.$2);
  });
  final byDate = <String, List<String>>{};
  for (final row in sorted) {
    byDate.putIfAbsent(row.$1, () => []).add(row.$3);
  }
  return [for (final e in byDate.entries) DueDay(e.key, e.value)];
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The zone the profile in [backend] says and its [dueDays] from [now]; null when the vault does not
/// answer a profile with a zone (nothing is scheduled then).
Future<({String zone, List<DueDay> days})?> dueListOf(
  LocalBackend backend, {
  required DateTime now,
}) async {
  final me = await backend.handle('GET', '/v1/me', const {}, null);
  final body = me?.body;
  if (me == null || me.status != 200 || body is! Map) return null;
  final zone = body['timezone'];
  if (zone is! String) return null;
  return (zone: zone, days: await dueDays(backend, today: todayIn(zone, now.toUtc())));
}
