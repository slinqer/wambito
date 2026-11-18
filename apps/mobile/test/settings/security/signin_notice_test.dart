// The sign-in notice (phone-first spec 8.3, ruling 16): what counts as a new device, the first
// silent look, "OK", and "That wasn't me" (one device: its removal sheet; several: Settings).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wambito/local/keys.dart' show WrapDto;
import 'package:wambito/local/vault_session.dart' show VaultSession;
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/theme/theme.dart';
import 'package:wambito/router.dart' show routerProvider;
import 'package:wambito/security/screen_lock.dart' show LockCheck, screenLockProvider;
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/settings/security/signin_notice.dart';
import 'package:wambito/vault/vault_providers.dart' show vaultSessionProvider;

import '../../support/fonts.dart';
import '../../support/plain_account.dart';
import '../../support/ui_app.dart';
import 'fake_security.dart';

class _FakeSession extends Fake implements VaultSession {}

class _Store implements SeenDevicesStore {
  _Store([this.ids]);

  Set<String>? ids;
  int keeps = 0;

  @override
  Future<Set<String>?> read(String userId) async => ids;

  @override
  Future<void> keep(String userId, Set<String> next) async {
    keeps += 1;
    ids = next;
  }
}

SecuritySnapshot _snapshot(List<WrapDto> devices) => SecuritySnapshot(
  wraps: [
    wrapOf('r', 'recovery'),
    wrapOf(ownId, 'device', label: 'Pixel 9', createdAt: '2026-10-02T10:00:00Z'),
    ...devices,
  ],
  ownId: ownId,
  revoked: const [],
  verified: {for (final d in devices) d.id},
  unreadable: 0,
);

final _laptop = wrapOf(
  laptopId,
  'device',
  label: 'Firefox on Linux',
  createdAt: '2026-10-03T10:00:00Z',
);
final _safari = wrapOf(
  forgedId,
  'device',
  label: 'Safari on iOS',
  createdAt: '2026-10-04T10:00:00Z',
);

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (c, s) => const SizedBox()),
    GoRoute(path: '/settings', builder: (c, s) => const Text('settings page')),
  ],
);

Future<void> _pump(WidgetTester t, SecurityApi? security, _Store store, {GoRouter? router}) async {
  t.view
    ..physicalSize = const Size(824, 2400)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        securityApiProvider.overrideWithValue(security),
        seenDevicesStoreProvider.overrideWithValue(store),
        screenLockProvider.overrideWithValue(FakeLock(LockCheck.passed)),
        if (router != null) routerProvider.overrideWithValue(router),
      ],
      child: uiApp(
        Column(
          children: [
            Consumer(
              builder: (context, ref, _) => TextButton(
                key: const Key('look'),
                onPressed: () => showSigninNotice(context, ref),
                child: const Text('look'),
              ),
            ),
            // the router the notice pushes Settings on, in the tree so that it parses its routes
            if (router != null) SizedBox(height: 40, child: Router.withConfig(config: router)),
          ],
        ),
        locale: const Locale('en'),
      ),
    ),
  );
}

Future<void> _look(WidgetTester t) async {
  await t.tap(find.byKey(const Key('look')));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('newDevices', () {
    final wraps = [
      wrapOf('r', 'recovery'),
      wrapOf(ownId, 'device'),
      wrapOf(laptopId, 'device'),
      wrapOf('p', 'passkey', ref: 'c'),
    ];

    test('this phone\'s own wrap never counts', () {
      expect(newDevices(wraps, seen: {}, ownId: ownId).map((w) => w.id), [laptopId]);
    });

    test('a device already seen does not count, and no first look is empty', () {
      expect(newDevices(wraps, seen: {laptopId}, ownId: ownId), isEmpty);
      expect(newDevices(wraps, seen: null, ownId: ownId), isEmpty);
    });
  });

  testWidgets('the first look records every device and says nothing', (t) async {
    final store = _Store();
    await _pump(t, FakeSecurity(_snapshot([_laptop, _safari])), store);
    await _look(t);
    expect(find.textContaining('A session was opened'), findsNothing);
    expect(store.ids, {ownId, laptopId, forgedId});
  });

  testWidgets('a device wrap added since shows its label once', (t) async {
    final store = _Store({ownId, laptopId});
    await _pump(t, FakeSecurity(_snapshot([_laptop, _safari])), store);
    await _look(t);
    expect(find.text('A session was opened on Safari on iOS'), findsOneWidget);
    expect(find.byKey(const Key('signinNotice.notMe')), findsOneWidget);
    // a device the person had already seen is not named
    expect(find.textContaining('Firefox'), findsNothing);
  });

  testWidgets('OK records it; it never shows again', (t) async {
    final store = _Store({ownId});
    await _pump(t, FakeSecurity(_snapshot([_laptop])), store);
    await _look(t);
    expect(find.text('A session was opened on Firefox on Linux'), findsOneWidget);
    await t.tap(find.byKey(const Key('signinNotice.ok')));
    await t.pumpAndSettle();
    expect(store.ids, {ownId, laptopId});
    await _look(t);
    expect(find.textContaining('A session was opened'), findsNothing);
  });

  testWidgets('closing it without answering leaves it to be said again', (t) async {
    final store = _Store({ownId});
    await _pump(t, FakeSecurity(_snapshot([_laptop])), store);
    await _look(t);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.textContaining('A session was opened'), findsNothing);
    expect(store.ids, {ownId});
    await _look(t);
    expect(find.text('A session was opened on Firefox on Linux'), findsOneWidget);
  });

  testWidgets('a device the person removed is no longer new nor kept', (t) async {
    final store = _Store({ownId, laptopId, forgedId});
    await _pump(t, FakeSecurity(_snapshot([_laptop])), store);
    await _look(t);
    expect(find.textContaining('A session was opened'), findsNothing);
    expect(store.ids, {ownId, laptopId});
  });

  testWidgets("That wasn't me with one new device opens RemoveDeviceSheet for that device's row", (
    t,
  ) async {
    final store = _Store({ownId});
    await _pump(t, FakeSecurity(_snapshot([_laptop])), store);
    await _look(t);
    await t.tap(find.byKey(const Key('signinNotice.notMe')));
    await t.pumpAndSettle();
    expect(find.text('Remove Firefox on Linux?'), findsOneWidget);
    expect(find.byKey(const Key('security.remove.key')), findsOneWidget);
    // it was seen: the same device is not said again
    expect(store.ids, {ownId, laptopId});
  });

  testWidgets('with two it opens Settings → Security', (t) async {
    final store = _Store({ownId});
    final router = _router();
    await _pump(t, FakeSecurity(_snapshot([_laptop, _safari])), store, router: router);
    await _look(t);
    expect(find.text('A session was opened on Safari on iOS'), findsOneWidget);
    expect(find.text('1 more device was added too.'), findsOneWidget);
    await t.tap(find.byKey(const Key('signinNotice.notMe')));
    await t.pumpAndSettle();
    expect(router.state.uri.path, '/settings');
    expect(find.textContaining('Remove '), findsNothing);
  });

  testWidgets('the phone that approved the browser is told too (ruling 16)', (t) async {
    final store = _Store({ownId});
    final security = FakeSecurity(_snapshot([_laptop]));
    await _pump(t, security, store);
    // the person approved the web sign-in from this phone: nothing marks the wrap as theirs
    await _look(t);
    expect(find.text('A session was opened on Firefox on Linux'), findsOneWidget);
  });

  testWidgets('no vault, no notice, no /v2/keys call', (t) async {
    final store = _Store();
    final security = FakeSecurity(_snapshot([_laptop]));
    // a `plain` account has no open vault, so no SecurityApi: nothing is read or recorded
    await _pump(t, null, store);
    await _look(t);
    expect(find.textContaining('A session was opened'), findsNothing);
    expect(store.keeps, 0);
    expect(security.loads, 0);
  });

  testWidgets('the host asks nothing of a plain account on start', (t) async {
    final store = _Store();
    final security = FakeSecurity(_snapshot([_laptop]));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          plainAccount(),
          vaultSessionProvider.overrideWithValue(null),
          securityApiProvider.overrideWithValue(security),
          seenDevicesStoreProvider.overrideWithValue(store),
        ],
        child: uiApp(const SigninNoticeHost(child: SizedBox()), locale: const Locale('en')),
      ),
    );
    await t.pumpAndSettle();
    expect(security.loads, 0);
    expect(store.keeps, 0);
  });

  group('SigninNoticeHost with a Ready vault', () {
    late GoRouter router;

    Future<void> pumpHost(WidgetTester t, _Store store, {String at = '/'}) async {
      router = GoRouter(
        initialLocation: at,
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/other',
            builder: (c, s) => const Scaffold(body: Text('other')),
          ),
        ],
      );
      t.view
        ..physicalSize = const Size(824, 2400)
        ..devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            vaultSessionProvider.overrideWithValue(_FakeSession()),
            routerProvider.overrideWithValue(router),
            securityApiProvider.overrideWithValue(FakeSecurity(_snapshot([_laptop]))),
            seenDevicesStoreProvider.overrideWithValue(store),
            screenLockProvider.overrideWithValue(FakeLock(LockCheck.passed)),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: nightTheme,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => SigninNoticeHost(child: child!),
          ),
        ),
      );
      await t.pumpAndSettle();
      // the host's look polls every 250 ms until home is free
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
    }

    Future<void> resume(WidgetTester t) async {
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
    }

    final notice = find.text('A session was opened on Firefox on Linux');

    testWidgets('one notice on start', (t) async {
      await pumpHost(t, _Store({ownId}));
      expect(notice, findsOneWidget);
      await t.tap(find.byKey(const Key('signinNotice.ok')));
      await t.pumpAndSettle();
      expect(notice, findsNothing);
    });

    testWidgets('none while another route is open; it shows once home is free', (t) async {
      await pumpHost(t, _Store({ownId}), at: '/other');
      expect(notice, findsNothing);
      router.go('/');
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(notice, findsOneWidget);
    });

    testWidgets('a resume says it again only when the answer was not recorded', (t) async {
      await pumpHost(t, _Store({ownId}));
      // closed without answering: nothing recorded
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(notice, findsNothing);
      await resume(t);
      expect(notice, findsOneWidget);
      await t.tap(find.byKey(const Key('signinNotice.ok')));
      await t.pumpAndSettle();
      await resume(t);
      expect(notice, findsNothing);
    });

    testWidgets('a resume while the notice is open does not open a second one', (t) async {
      await pumpHost(t, _Store({ownId}));
      await resume(t);
      expect(notice, findsOneWidget);
      await t.tap(find.byKey(const Key('signinNotice.ok')));
      await t.pumpAndSettle();
      expect(notice, findsNothing);
    });
  });
}
