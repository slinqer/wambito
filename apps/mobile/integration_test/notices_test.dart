// The two local notices on an Android emulator against the dev stack (`docker compose up -d` at
// the repo root), as docs/mobile/setup.md describes (spec section 7.2):
//
//   flutter test integration_test/notices_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000
//
// The permission question is asked on a phone that has not been asked, so the first test needs the
// permission not yet given (a fresh install, or `adb shell pm revoke com.wambito.app
// android.permission.POST_NOTIFICATIONS`). The second needs it given, which only a person or adb
// can do: `adb shell pm grant com.wambito.app android.permission.POST_NOTIFICATIONS`
// (the test tells which one is missing). The jobs run for real through WorkManager, reading the
// session where the app keeps it; the notice's tap is the very PendingIntent the shade would send.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture/parser/dates.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;
import 'package:wambito/notices/notice_platform.dart';
import 'package:wambito/settings/settings_screen.dart';
import 'package:wambito/settings/settings_store.dart';

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');
const _test = MethodChannel('wambito/test');
const _platform = ChannelNoticePlatform();

/// For a person (or adb) to tap the real notification on the shade instead of the test sending its
/// PendingIntent: `--dart-define=TAP_BY_HAND=true`.
const _tapByHand = bool.fromEnvironment('TAP_BY_HAND');

final _http = Dio(BaseOptions(validateStatus: (_) => true));

Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

/// A new guest, on the entry screen's button.
Future<void> _startAsGuest(WidgetTester tester) async {
  await SessionStore().clear();
  await tester.pumpWidget(await app.bootstrap());
  await _pumpUntil(tester, find.byKey(const Key('entry.start')));
  // The API limits new guests from one address to a few in a row: wait and try again.
  for (var attempt = 0; find.byType(HomeScreen).evaluate().isEmpty; attempt++) {
    if (attempt == 8) throw TestFailure('Could not start a guest');
    await tester.tap(find.byKey(const Key('entry.start')));
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(end) && find.byType(HomeScreen).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a guest who has not been asked is asked once, with one sentence on why', (
    tester,
  ) async {
    if (await _platform.permission() != NoticePermission.askable) {
      fail('Needs the notification permission not given: adb shell pm revoke … POST_NOTIFICATIONS');
    }
    await _startAsGuest(tester);
    await _pumpUntil(tester, find.byKey(const Key('notices.ask')));
    expect(tester.widget<Text>(find.byKey(const Key('notices.askWhy'))).data, contains('45'));
    // The question is a sheet: let it finish sliding in before pressing in it.
    await tester.pump(const Duration(milliseconds: 500));
    // "Ahora no": Android's own prompt is not shown, and the question is not asked again.
    await tester.tap(find.byKey(const Key('notices.askLater')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('notices.ask')), findsNothing);
    expect(await _platform.permission(), NoticePermission.askable);
    await SessionStore().clear();
  });

  testWidgets('Hoy vence… posts one notice for what is due today, and tapping it opens home', (
    tester,
  ) async {
    if (await _platform.permission() != NoticePermission.granted) {
      fail('Needs the notification permission: adb shell pm grant … POST_NOTIFICATIONS');
    }
    // The app in Spanish, whatever the emulator speaks: the notice follows the app's language.
    await const SecureSettingsStore().write(localeKey, 'es');
    await _startAsGuest(tester);
    final token = (await SessionStore().read())!.token;

    // The profile's zone is the server's word, and "today" is read in it. "Hoy vence…" never goes
    // out before 9:00 there, so the profile gets a zone where it is about noon right now.
    final offset = () {
      final hours = 12 - DateTime.now().toUtc().hour;
      return hours > 12 ? hours - 24 : (hours < -12 ? hours + 24 : hours);
    }();
    final zone = offset == 0 ? 'Etc/GMT' : (offset > 0 ? 'Etc/GMT-$offset' : 'Etc/GMT+${-offset}');
    final patched = await _http.patch<Map<String, dynamic>>(
      '$_server/api/v1/me',
      data: {'timezone': zone},
      options: _auth(token),
    );
    expect(patched.statusCode, 200, reason: '${patched.data}');
    final today = todayIn(zone, DateTime.now().toUtc());
    final category = await _http.post<Map<String, dynamic>>(
      '$_server/api/v1/categories',
      data: {'name': 'Avisos', 'kind': 'expense', 'icon': '🏠', 'color': '#2fd388'},
      options: _auth(token),
    );
    expect(category.statusCode, 201, reason: '${category.data}');
    for (final (name, amount) in [('Arriendo', -150000000), ('Spotify', -1790000)]) {
      final made = await _http.post<Map<String, dynamic>>(
        '$_server/api/v1/recurrences',
        data: {
          'name': name,
          'amount': amount,
          'categoryId': category.data!['id'],
          'frequency': 'monthly',
          'dayOfMonth': int.parse(today.substring(8)),
          'startDate': today,
        },
        options: _auth(token),
      );
      expect(made.statusCode, 201, reason: '${made.data}');
      // Created seconds apart, so the notice lists them in the order they were made.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }

    // The app comes back to the foreground: it now sees a recurring payment and notices allowed,
    // so it schedules "Hoy vence…" (it is not scheduled for someone with nothing to announce).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(await _test.invokeMethod<String>('runDueNotice'), 'posted');
    expect(await _test.invokeMethod<List<Object?>>('activeNotices'), [
      'Hoy vencen Arriendo y Spotify',
    ]);

    // Tapping it from anywhere in the app comes back to home.
    final context = tester.element(find.byType(HomeScreen));
    GoRouter.of(context).go('/settings');
    await _pumpUntil(tester, find.byType(SettingsScreen));
    if (!_tapByHand) expect(await _test.invokeMethod<bool>('tapDueNotice'), isTrue);
    await _pumpUntil(
      tester,
      find.byType(HomeScreen),
      timeout: _tapByHand ? const Duration(minutes: 3) : const Duration(seconds: 30),
    );
    expect(find.byType(SettingsScreen), findsNothing);

    // Signing out takes the notice off the shade: it names this person's payments. (Sent by the
    // test, the tap leaves it there; tapped by hand, the shade already took it.)
    if (!_tapByHand) {
      expect(await _test.invokeMethod<List<Object?>>('activeNotices'), [
        'Hoy vencen Arriendo y Spotify',
      ]);
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    await container.read(sessionProvider.notifier).signOut(discardGuest: true);
    final end = DateTime.now().add(const Duration(seconds: 10));
    var left = await _test.invokeMethod<List<Object?>>('activeNotices');
    while (left!.isNotEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      left = await _test.invokeMethod<List<Object?>>('activeNotices');
    }
    expect(left, isEmpty);

    await SessionStore().clear();
    await const SecureSettingsStore().delete(localeKey);
  });
}
