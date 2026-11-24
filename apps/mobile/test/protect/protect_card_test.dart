// When home's "Protect your data" card is due (phone-first spec 5.2): 7 days or 10 movements, then
// 14, then every 30.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/protect/protect_card.dart';

void main() {
  final firstOpen = DateTime.utc(2026, 11, 1, 10);
  DateTime day(int n) => firstOpen.add(Duration(days: n));
  bool due(ProtectCardState state, DateTime now, {int movements = 0}) =>
      protectCardDue(state, movements: movements, now: now);

  final fresh = ProtectCardState(firstOpen: firstOpen);

  test('not due at 6 days and 9 movements', () {
    expect(due(fresh, day(6), movements: 9), isFalse);
  });

  test('due at 7 days', () {
    expect(due(fresh, day(7)), isTrue);
  });

  test('due on day 1 at 10 movements', () {
    expect(due(fresh, day(1), movements: 10), isTrue);
  });

  test('dismissed on day 10: not due on day 23, due on day 24', () {
    final dismissed = ProtectCardState(firstOpen: firstOpen, lastDismissed: day(10), dismissals: 1);
    expect(due(dismissed, day(23), movements: 50), isFalse);
    expect(due(dismissed, day(24)), isTrue);
  });

  test('second dismissal: due 30 days later, not 29', () {
    final twice = ProtectCardState(firstOpen: firstOpen, lastDismissed: day(24), dismissals: 2);
    expect(due(twice, day(24 + 29)), isFalse);
    expect(due(twice, day(24 + 30)), isTrue);
  });

  test('third and later: every 30', () {
    final thrice = ProtectCardState(firstOpen: firstOpen, lastDismissed: day(60), dismissals: 3);
    expect(due(thrice, day(89)), isFalse);
    expect(due(thrice, day(90)), isTrue);
    final fifth = ProtectCardState(firstOpen: firstOpen, lastDismissed: day(120), dismissals: 5);
    expect(due(fifth, day(149)), isFalse);
    expect(due(fifth, day(150)), isTrue);
  });

  test('a clock that moved back restarts the wait from now', () {
    final later = ProtectCardState(firstOpen: day(30));
    // now (day 10) is before firstOpen: counts as now, so not due until 7 days after now
    expect(due(later, day(10)), isFalse);
    final dismissed = ProtectCardState(firstOpen: day(0), lastDismissed: day(40), dismissals: 1);
    expect(due(dismissed, day(10)), isFalse);
  });

  test('a time corrected after a forward jump is not stuck in the future', () {
    final dismissed = ProtectCardState(firstOpen: day(0), lastDismissed: day(400), dismissals: 1);
    // the clock is back at day 20: the dismissal counts as day 20, due again 14 days on
    expect(due(dismissed, day(20)), isFalse);
    final reread = ProtectCardState(firstOpen: day(0), lastDismissed: day(20), dismissals: 1);
    expect(due(reread, day(34)), isTrue);
  });

  test('the state round-trips through JSON, and junk reads as nothing', () {
    final state = ProtectCardState(firstOpen: firstOpen, lastDismissed: day(3), dismissals: 2);
    final back = ProtectCardState.fromJson(state.toJson())!;
    expect(back.firstOpen, firstOpen);
    expect(back.lastDismissed, day(3));
    expect(back.dismissals, 2);
    expect(ProtectCardState.fromJson('nope'), isNull);
    expect(ProtectCardState.fromJson({'firstOpen': 'x'}), isNull);
  });
}
