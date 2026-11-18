// The welcome on an Android emulator against the dev stack (`docker compose up -d` at the repo root:
// API, Postgres, Mailpit), as docs/mobile/setup.md describes:
//
//   flutter test integration_test/welcome_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000 \
//     --dart-define=MAILPIT_URL=http://10.0.2.2:8025
//
// A new email user (the code arrives in Mailpit) is sent to the welcome and goes through every step
// against the real API: the currency, the import's "No, empiezo de cero", the categories, the
// budgets. What the server holds afterwards is checked. The emulator's language decides the copy, so
// controls are found by key.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;

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
  await tester.pump();
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

Future<Map<String, dynamic>> _me() async {
  final res = await _http.get<Map<String, dynamic>>('$_server/api/v1/me', options: await _auth());
  expect(res.statusCode, 200);
  return res.data!;
}

Future<List<dynamic>> _categories() async {
  final res = await _http.get<List<dynamic>>('$_server/api/v1/categories', options: await _auth());
  expect(res.statusCode, 200);
  return res.data!;
}

/// Signs in as a new email user, and waits for the welcome.
Future<String> _signInNew(WidgetTester tester, String label) async {
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
  return email;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a new email user completes the welcome: currency, import, categories, budgets', (
    tester,
  ) async {
    await _signInNew(tester, 'mobile-welcome');
    // Not onboarded yet, on the server and on the phone.
    expect((await _me())['onboardingCompletedAt'], isNull);
    expect((await SessionStore().read())?.onboardingPending, isTrue);
    expect(find.byType(HomeScreen), findsNothing);

    await _tap(tester, 'welcome.setup');
    await _pumpUntil(tester, find.byKey(const Key('welcome.step.currency')));
    // The person chooses for real: dollars, wherever the phone is.
    await _tap(tester, 'welcome.currency.USD');
    await _tap(tester, 'welcome.next');
    await _pumpUntil(tester, find.byKey(const Key('welcome.step.import')));
    expect((await _me())['currency'], 'USD');

    // The app is killed here and started again: the welcome is where it was left (an account that
    // has not finished it is sent to it from everywhere).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(await app.bootstrap());
    await _pumpUntil(tester, find.byKey(const Key('welcome.step.welcome')));
    expect(find.byType(HomeScreen), findsNothing);
    await _tap(tester, 'welcome.setup');
    await _pumpUntil(tester, find.byKey(const Key('welcome.step.currency')));
    await _tap(tester, 'welcome.next');
    await _pumpUntil(tester, find.byKey(const Key('welcome.step.import')));

    await _tap(tester, 'import.fresh');
    await _pumpUntil(tester, find.byKey(const Key('welcome.step.categories')));
    await _tap(tester, 'welcome.next');
    await _pumpUntil(tester, find.byKey(const Key('welcome.step.budgets')));
    // The suggestions were made, and the first spending one has a budget field.
    final categories = await _categories();
    expect(categories.where((c) => (c as Map)['kind'] == 'expense'), hasLength(7));
    expect(categories.where((c) => (c as Map)['kind'] == 'income'), hasLength(1));
    final first = (categories.firstWhere((c) => (c as Map)['kind'] == 'expense') as Map)['id'];
    await _pumpUntil(tester, find.byKey(Key('budget.field.$first')));
    await tester.enterText(find.byKey(Key('budget.field.$first')), '300');
    await tester.pump();
    await _tap(tester, 'welcome.next');
    await _pumpUntil(tester, find.byType(HomeScreen));

    final me = await _me();
    expect(me['onboardingCompletedAt'], isNotNull);
    expect(me['currency'], 'USD');
    expect((await SessionStore().read())?.onboardingPending, isFalse);
    final after = await _categories();
    expect((after.firstWhere((c) => (c as Map)['id'] == first) as Map)['currentBudget'], 30000);

    // Finished: the welcome never shows again, not even after a restart.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(await app.bootstrap());
    await _pumpUntil(tester, find.byType(HomeScreen));
    expect(find.byKey(const Key('welcome.page')), findsNothing);
  });

  testWidgets('Entrar directo: the device\'s currency, the suggested categories, then home', (
    tester,
  ) async {
    await _signInNew(tester, 'mobile-direct');
    await _tap(tester, 'welcome.direct');
    await _pumpUntil(tester, find.byType(HomeScreen));

    final me = await _me();
    expect(me['onboardingCompletedAt'], isNotNull);
    expect(['COP', 'USD', 'EUR'], contains(me['currency']));
    expect(await _categories(), hasLength(8));
  });
}
