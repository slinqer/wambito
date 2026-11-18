// Deleting the account on an Android emulator against the dev stack (`docker compose up -d` at the
// repo root: API, Postgres, Mailpit), as docs/mobile/setup.md describes:
//
//   flutter test integration_test/delete_account_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000 \
//     --dart-define=MAILPIT_URL=http://10.0.2.2:8025
//
// ONLY a throwaway account: the test makes a new email user on the dev stack, never touches anyone
// else's, and deletes that one for good. It types the email in Settings and confirms against the
// real API, and then checks what is left: the server no longer knows the token, and the phone holds
// nothing of the account (the session, the home cache, the widget's figures) and shows the entry
// screen. The emulator's language decides the copy, so controls are found by key.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/main.dart' as app;
import 'package:wambito/ui/press_button.dart';

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');
const _mailpit = String.fromEnvironment('MAILPIT_URL', defaultValue: 'http://10.0.2.2:8025');

final _http = Dio(BaseOptions(validateStatus: (_) => true));

String _freshEmail(String label) =>
    '$label-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}@wambito.test';

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  // What was on screen, to say what the person would have seen.
  final texts = [
    for (final e in find.byType(Text).evaluate())
      (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText(),
  ];
  throw TestFailure('Timed out waiting for $finder; the screen says: $texts');
}

/// Brings the widget well into view (a third of the way down), as a person scrolling to it would.
/// `ensureVisible` leaves it at the edge, where the bottom bar or the top of a short phone can still
/// cover the middle of it and the tap derives an offset that is off screen.
/// The page can still move after the first scroll (what loads above it), so it looks again that the
/// middle of the widget is on screen before the tap.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var attempt = 0; attempt < 5; attempt++) {
    final element = tester.element(finder.first);
    if (Scrollable.maybeOf(element) != null) {
      await Scrollable.ensureVisible(element, alignment: 0.3);
      await tester.pump(const Duration(milliseconds: 300));
    }
    final center = tester.getCenter(finder.first);
    if (center.dy > 0 && center.dy < size.height) return;
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _pumpUntil(tester, find.byKey(Key(key)));
  await _reveal(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<String> _codeTo(String email) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(end)) {
    final list = await _http.get<Map<String, dynamic>>('$_mailpit/api/v1/messages?limit=100');
    final messages = (list.data?['messages'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .where(
          (m) => (m['To'] as List<dynamic>).any(
            (to) => (to as Map<String, dynamic>)['Address'].toString().toLowerCase() == email,
          ),
        );
    if (messages.isNotEmpty) {
      return RegExp(r'(\d{6})$').firstMatch(messages.first['Subject'] as String)!.group(1)!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TestFailure('No email to $email in Mailpit');
}

Future<Options> _auth() async {
  final stored = await SessionStore().read();
  expect(stored, isNotNull, reason: 'the app stored a session');
  return Options(headers: {'Authorization': 'Bearer ${stored!.token}'});
}

/// A new email user, through the welcome ("Entrar directo"), on home, with one movement.
Future<String> _signInWithAMovement(WidgetTester tester, String label) async {
  final email = _freshEmail(label);
  await SessionStore().clear();
  await tester.pumpWidget(await app.bootstrap());
  await _pumpUntil(tester, find.byKey(const Key('entry.haveAccount')));
  await _tap(tester, 'entry.haveAccount');
  await _pumpUntil(tester, find.byKey(const Key('entry.email')));
  await tester.enterText(find.byKey(const Key('entry.email')), email);
  await _tap(tester, 'entry.send');
  await _pumpUntil(tester, find.byKey(const Key('entry.code')));
  await tester.enterText(find.byKey(const Key('entry.code')), await _codeTo(email));
  await _tap(tester, 'entry.submitCode');
  await _pumpUntil(tester, find.byKey(const Key('welcome.step.welcome')));
  await _tap(tester, 'welcome.direct');
  await _pumpUntil(tester, find.byType(HomeScreen));
  final categories = await _http.get<List<dynamic>>(
    '$_server/api/v1/categories',
    options: await _auth(),
  );
  final category =
      (categories.data!.firstWhere((c) => (c as Map)['kind'] == 'expense') as Map)['id'];
  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final made = await _http.post<Map<String, dynamic>>(
    '$_server/api/v1/transactions',
    data: {'name': 'Cafe del export', 'amount': -350, 'categoryId': category, 'date': today},
    options: (await _auth())..headers!['Idempotency-Key'] = 'export-${email.hashCode}-1',
  );
  expect(made.statusCode, 201, reason: '${made.data}');
  return email;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a throwaway account is deleted for good, and the phone is cleared', (tester) async {
    final email = await _signInWithAMovement(tester, 'mobile-delete');
    final token = (await SessionStore().read())!.token;
    final bearer = Options(headers: {'Authorization': 'Bearer $token'});
    // Home was loaded: the phone holds the account's figures.
    expect(await const SecureHomeCacheStore().read(), isNotNull);
    expect(await const HomeWidgetStore().read(widgetSnapshotKey), contains('"signedIn":true'));

    GoRouter.of(tester.element(find.byType(HomeScreen))).go('/settings');
    await _pumpUntil(tester, find.byKey(const Key('settings.delete')));
    await _tap(tester, 'settings.delete');
    await _pumpUntil(tester, find.byKey(const Key('settings.delete.field')));
    // Off until the email is typed.
    expect(
      tester.widget<PressButton>(find.byKey(const Key('settings.delete.confirm'))).onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('settings.delete.field')),
      ' ${email.toUpperCase()} ',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _tap(tester, 'settings.delete.confirm');
    await _pumpUntil(
      tester,
      find.byKey(const Key('entry.start')),
      timeout: const Duration(seconds: 60),
    );

    // The server no longer has the account: its token is refused.
    final me = await _http.get<Object?>('$_server/api/v1/me', options: bearer);
    expect(me.statusCode, 401);
    // The phone holds nothing of it.
    expect(await SessionStore().read(), isNull);
    expect(await const SecureHomeCacheStore().read(), isNull);
    final widget = await const HomeWidgetStore().read(widgetSnapshotKey);
    expect(widget, contains('"signedIn":false'));
    expect(widget, isNot(contains('remaining')));
    expect(find.byType(HomeScreen), findsNothing);
  });
}
