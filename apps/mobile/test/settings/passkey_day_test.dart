import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wambito/settings/passkeys_section.dart';

/// The day a passkey, a device or an assistant's grant is shown with: the web's
/// `Intl.DateTimeFormat(locale, { dateStyle: "medium", timeZone })` (PasskeysSection.tsx and
/// AgentsScreen.tsx `formatDay`), in the person's time zone.
void main() {
  setUpAll(() => initializeDateFormatting());

  final at = DateTime.utc(2026, 10, 2, 9);

  test('es and en write the short month', () {
    expect(passkeyDay(at, 'es', 'Europe/Madrid'), '2 oct 2026');
    expect(passkeyDay(at, 'en', 'Europe/Madrid'), 'Oct 2, 2026');
  });

  test('it writes the short month', () {
    expect(passkeyDay(at, 'it', 'Europe/Madrid'), '2 ott 2026');
  });

  test('pt writes the day and month with two digits, as pt-PT medium does', () {
    expect(passkeyDay(at, 'pt', 'Europe/Madrid'), '02/10/2026');
    expect(passkeyDay(DateTime.utc(2026, 12, 25, 12), 'pt', 'Europe/Lisbon'), '25/12/2026');
  });

  test('the day is the one in the person\'s time zone', () {
    // 23:30 UTC on 1 October is already 2 October in Madrid, and still 1 October in Bogotá.
    final late = DateTime.utc(2026, 10, 1, 23, 30);
    expect(passkeyDay(late, 'pt', 'Europe/Madrid'), '02/10/2026');
    expect(passkeyDay(late, 'es', 'America/Bogota'), '1 oct 2026');
  });
}
