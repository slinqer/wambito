// Port of packages/core/src/dates.ts. Months are `YYYY-MM`, dates `YYYY-MM-DD`.
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final _month = RegExp(r'^(\d{4})-(\d{2})$');
final _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

String _pad(int n, [int width = 2]) => n.toString().padLeft(width, '0');

(int, int) _parts(String m) {
  final match = _month.firstMatch(m);
  if (match == null) throw RangeError('Invalid month: $m');
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}

bool isMonth(String s) {
  final match = _month.firstMatch(s);
  if (match == null) return false;
  final month = int.parse(match.group(2)!);
  return month >= 1 && month <= 12;
}

bool isIsoDate(String s) {
  final match = _date.firstMatch(s);
  if (match == null) return false;
  final m = '${match.group(1)}-${match.group(2)}';
  final day = int.parse(match.group(3)!);
  return isMonth(m) && day >= 1 && day <= daysInMonth(m);
}

int daysInMonth(String m) {
  final (year, month) = _parts(m);
  return DateTime.utc(year, month + 1, 0).day;
}

String monthOf(String date) => date.substring(0, 7);

String firstDay(String m) {
  _parts(m);
  return '$m-01';
}

String lastDay(String m) => '$m-${_pad(daysInMonth(m))}';

/// [m] moved by [n] months, across years both ways.
String addMonths(String m, int n) {
  final (year, month) = _parts(m);
  final index = year * 12 + (month - 1) + n;
  final years = (index / 12).floor();
  return '${_pad(years, 4)}-${_pad(index - years * 12 + 1)}';
}

List<String> monthsBetween(String from, String to) {
  final result = <String>[];
  for (var m = from; m.compareTo(to) <= 0; m = addMonths(m, 1)) {
    result.add(m);
  }
  return result;
}

var _tzReady = false;

void _ensureTimeZones() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

/// Today in [timeZone] (an IANA name) at the instant [now], as `YYYY-MM-DD`. Throws
/// `LocationNotFoundException` for an unknown zone, as `Intl.DateTimeFormat` throws in the
/// TypeScript.
String todayIn(String timeZone, [DateTime? now]) {
  _ensureTimeZones();
  final local = tz.TZDateTime.from((now ?? DateTime.now()).toUtc(), tz.getLocation(timeZone));
  return '${_pad(local.year, 4)}-${_pad(local.month)}-${_pad(local.day)}';
}

final _zoneName = RegExp(r'^[A-Za-z][A-Za-z0-9_+-]*(?:/[A-Za-z0-9_+-]+)*$');

/// Whether [zone] is a named IANA time zone the bundled database knows (offsets like `+05:00`
/// are refused).
bool isValidTimeZone(String zone) {
  if (zone.length > 64 || !_zoneName.hasMatch(zone)) return false;
  _ensureTimeZones();
  try {
    tz.getLocation(zone);
    return true;
  } on tz.LocationNotFoundException {
    return false;
  }
}
