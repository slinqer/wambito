// On an Android emulator against the dev stack (`docker compose up -d` at the repo root: API,
// Postgres, Mailpit), as docs/mobile/setup.md describes:
//
//   flutter test integration_test -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000 \
//     --dart-define=MAILPIT_URL=http://10.0.2.2:8025
//
// A new email account has not been through the welcome (no onboardingCompletedAt), so signing in with
// a code, a link or an intent lands on it (integration_test/welcome_test.dart goes through it); a
// guest, and a guest that saves its progress with an email, land on home.
//
// The emulator reaches the Mac at 10.0.2.2. Buttons are found by key: the emulator's language
// decides the copy (the widget tests check the Spanish and English words).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');
const _mailpit = String.fromEnvironment('MAILPIT_URL', defaultValue: 'http://10.0.2.2:8025');

/// The host App Links are declared for in the manifest: a link there is dropped while the app talks
/// to another server (the dev stack), since only the configured server's links are taken.
const _appLinkHost = 'app.wambito.com';

final _http = Dio(BaseOptions(validateStatus: (_) => true));

/// A new address per call, so each test is a new user with its own email throttle.
String _freshEmail(String label) =>
    '$label-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}@wambito.test';

/// Pumps until [finder] finds something (network calls run in real time here).
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

/// What a person does with the keyboard that a field opened before reaching for a button under it:
/// puts it away. On a short phone with a soft keyboard (CI's emulator has a hardware one) the keyboard
/// covers the rest of the sheet, and a tap there would land on it.
Future<void> _dismissKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _pumpUntil(tester, find.byKey(Key(key)));
  // On a short phone the button may be below the fold: bring it up, as a person would.
  await _reveal(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

/// The newest email to [email] in Mailpit, waiting for it: its subject and plain text.
Future<({String subject, String text})> _mailTo(String email) async {
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
      final message = messages.first;
      final detail = await _http.get<Map<String, dynamic>>(
        '$_mailpit/api/v1/message/${message['ID']}',
      );
      return (subject: message['Subject'] as String, text: detail.data?['Text'] as String? ?? '');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TestFailure('No email to $email in Mailpit');
}

String _codeFrom(String subject) => RegExp(r'(\d{6})$').firstMatch(subject)!.group(1)!;

/// `GET /v1/me` with the token the app stored.
Future<Map<String, dynamic>> _me() async {
  final stored = await SessionStore().read();
  expect(stored, isNotNull, reason: 'the app stored a session');
  final res = await _http.get<Map<String, dynamic>>(
    '$_server/api/v1/me',
    options: Options(headers: {'Authorization': 'Bearer ${stored!.token}'}),
  );
  expect(res.statusCode, 200);
  return res.data!;
}

Future<void> _startApp(WidgetTester tester) async {
  await SessionStore().clear();
  await tester.pumpWidget(await app.bootstrap());
  await _pumpUntil(tester, find.byKey(const Key('entry.haveAccount')));
}

Future<void> _sendCodeTo(WidgetTester tester, String email) async {
  await _tap(tester, 'entry.haveAccount');
  await _pumpUntil(tester, find.byKey(const Key('entry.email')));
  await tester.enterText(find.byKey(const Key('entry.email')), email);
  await _tap(tester, 'entry.send');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Start creates a guest and lands on home', (tester) async {
    await _startApp(tester);

    await _tap(tester, 'entry.start');
    await _pumpUntil(tester, find.byType(HomeScreen));

    expect((await SessionStore().read())?.guest, isTrue);
    final me = await _me();
    expect(me['isAnonymous'], isTrue);
    // The guest's profile starts from the phone's time zone (x-wambito-timezone).
    // The server stores the canonical name, so an emulator's "Etc/UTC" comes back as "UTC".
    final zone = await const MethodChannel('wambito/device').invokeMethod<String>('timeZone');
    const utcAliases = {
      'Etc/UTC',
      'Etc/UCT',
      'Etc/Universal',
      'Etc/Zulu',
      'UCT',
      'Universal',
      'Zulu',
    };
    expect(me['timezone'], utcAliases.contains(zone) ? 'UTC' : zone);
  });

  testWidgets('the email code signs in', (tester) async {
    final email = _freshEmail('mobile-code');
    await _startApp(tester);

    await _sendCodeTo(tester, email);
    await _pumpUntil(tester, find.byKey(const Key('entry.code')));
    final mail = await _mailTo(email);
    await tester.enterText(find.byKey(const Key('entry.code')), _codeFrom(mail.subject));
    await _tap(tester, 'entry.submitCode');
    await _pumpUntil(tester, find.byKey(const Key('welcome.page')));

    final me = await _me();
    expect(me['email'], email);
    expect(me['isAnonymous'], isFalse);
  });

  testWidgets('opening the magic link in the app signs in', (tester) async {
    final email = _freshEmail('mobile-link');
    await _startApp(tester);
    await _sendCodeTo(tester, email);
    await _pumpUntil(tester, find.byKey(const Key('entry.code')));

    // The dev stack writes links to its web origin; the app takes only links for the server it
    // talks to, so the same query is opened on the dev server's host (debug builds declare it,
    // src/debug/AndroidManifest.xml), as Android delivers it: an ACTION_VIEW intent.
    final mail = await _mailTo(email);
    final link = Uri.parse(
      RegExp(r'https?://\S+/auth/verify\?\S+').firstMatch(mail.text)!.group(0)!,
    );
    // First on a host that is not the server the app talks to (the install's own App Link host,
    // while the app talks to the dev stack): another app could send that. It only opens the app,
    // and the code is still unused.
    final foreign = Uri(
      scheme: 'https',
      host: _appLinkHost,
      path: '/auth/verify',
      query: link.query,
    );
    await const MethodChannel('wambito/test').invokeMethod<void>('openLink', foreign.toString());
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HomeScreen), findsNothing);
    expect(await SessionStore().read(), isNull);

    final server = Uri.parse(_server);
    final appLink = Uri(
      scheme: server.scheme,
      host: server.host,
      port: server.port,
      path: '/auth/verify',
      query: link.query,
    );
    await const MethodChannel('wambito/test').invokeMethod<void>('openLink', appLink.toString());
    await _pumpUntil(tester, find.byKey(const Key('welcome.page')));

    final me = await _me();
    expect(me['email'], email);
  });

  testWidgets('a sign-in started in the app marks its link from=app, and the web page\'s '
      'intent:// form of it opens the app and signs in', (tester) async {
    final email = _freshEmail('mobile-intent');
    await _startApp(tester);
    await _sendCodeTo(tester, email);
    await _pumpUntil(tester, find.byKey(const Key('entry.code')));

    final mail = await _mailTo(email);
    final link = Uri.parse(
      RegExp(r'https?://\S+/auth/verify\?\S+').firstMatch(mail.text)!.group(0)!,
    );
    // The app sent x-wambito-client: android, so the API wrote from=app.
    expect(link.queryParameters['from'], 'app');

    // What apps/web/app/features/sign-in/open-in-app.ts builds for this page (the dev stack is
    // plain http, so scheme=http here; the product's is https): the same path and query, the app's
    // package, and the page without from=app as the fallback.
    final server = Uri.parse(_server);
    final query = link.query;
    final fallback = Uri(
      scheme: server.scheme,
      host: server.host,
      port: server.port,
      path: '/auth/verify',
      query: link.queryParameters.entries
          .where((e) => e.key != 'from')
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'),
    );
    final intentUri =
        'intent://${server.host}:${server.port}/auth/verify?$query'
        '#Intent;scheme=${server.scheme};package=com.wambito.app;'
        'S.browser_fallback_url=${Uri.encodeComponent(fallback.toString())};end';
    await const MethodChannel('wambito/test').invokeMethod<void>('openIntentUri', intentUri);
    await _pumpUntil(tester, find.byKey(const Key('welcome.page')));

    final me = await _me();
    expect(me['email'], email);
  });

  testWidgets(
    'a guest sees Guarda tu progreso; claiming an allowlisted email keeps every movement',
    (tester) async {
      final email = _freshEmail('mobile-claim');
      await _startApp(tester);
      await _tap(tester, 'entry.start');
      await _pumpUntil(tester, find.byType(HomeScreen));
      final guest = await _me();
      final guestToken = (await SessionStore().read())!.token;
      final auth = Options(headers: {'Authorization': 'Bearer $guestToken'});

      // A movement the guest noted before saving their progress.
      final name = 'Antes del correo ${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      final category = await _http.post<Map<String, dynamic>>(
        '$_server/api/v1/categories',
        data: {'name': name, 'kind': 'expense', 'icon': '🛒', 'color': '#2fd388'},
        options: auth,
      );
      expect(category.statusCode, 201, reason: '${category.data}');
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final movement = await _http.post<Map<String, dynamic>>(
        '$_server/api/v1/transactions',
        data: {'name': name, 'amount': -1500000, 'categoryId': category.data!['id'], 'date': today},
        options: auth.copyWith(headers: {...auth.headers!, 'Idempotency-Key': 'claim-$name'}),
      );
      expect(movement.statusCode, 201, reason: '${movement.data}');

      // Home offers "Guarda tu progreso" to a guest; it asks for the email and sends the code.
      await _tap(tester, 'home.account');
      await _tap(tester, 'home.saveProgress');
      await _pumpUntil(tester, find.byKey(const Key('progress.email')));
      await tester.enterText(find.byKey(const Key('progress.email')), email);
      await _dismissKeyboard(tester);
      await _tap(tester, 'progress.save');
      await _pumpUntil(tester, find.byKey(const Key('entry.code')));

      final mail = await _mailTo(email);
      await tester.enterText(find.byKey(const Key('entry.code')), _codeFrom(mail.subject));
      await _tap(tester, 'entry.submitCode');
      await _pumpUntil(tester, find.byType(HomeScreen));

      // The same user and the same token: no longer a guest, with the email, and the movement kept.
      final stored = await SessionStore().read();
      expect(stored?.token, guestToken);
      expect(stored?.guest, isFalse);
      final me = await _me();
      expect(me['id'], guest['id']);
      expect(me['email'], email);
      expect(me['isAnonymous'], isFalse);
      final kept = await _http.get<Map<String, dynamic>>(
        '$_server/api/v1/transactions',
        options: auth,
      );
      expect(kept.statusCode, 200);
      expect(
        (kept.data!['items'] as List<dynamic>).where((t) => (t as Map)['name'] == name),
        hasLength(1),
      );
      // And home no longer offers it (not in the face button's menu either).
      await _tap(tester, 'home.account');
      await _pumpUntil(tester, find.byKey(const Key('home.settings')));
      expect(find.byKey(const Key('home.saveProgress')), findsNothing);
    },
  );
}
