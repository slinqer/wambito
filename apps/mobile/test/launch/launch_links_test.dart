import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/add/add_sheet.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture/capture_sheet.dart';
import 'package:wambito/capture/engine/speech_engine.dart';
import 'package:wambito/entry/entry_screen.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/progress/progress_screen.dart';
import 'package:wambito/launch/launch_links.dart';
import 'package:wambito/router.dart';
import 'package:wambito/settings/security/approve_signin_screen.dart';
import 'package:wambito/settings/security/security_api.dart' show securityApiProvider;

import '../capture/fakes.dart';
import '../entry/fakes.dart' show FakeAuthApi;
import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../review/fakes.dart' show detected;
import '../settings/harness.dart';
import '../settings/security/fake_security.dart';

import 'package:wambito/ui/lk_icons.dart';

import '../support/icons.dart';

/// The links Android hands the app: one it was started with, and later ones.
class FakeLaunchLinks implements LaunchLinkSource {
  FakeLaunchLinks([this.initial]);

  String? initial;
  final _later = StreamController<String>.broadcast();

  @override
  Future<String?> takeInitial() async {
    final link = initial;
    initial = null;
    return link;
  }

  @override
  Stream<String> get links => _later.stream;

  void open(String link) => _later.add(link);
}

/// A server that takes its time to say who the account is (a bad connection): the profile read of a
/// start never comes back.
class _HangingProfile extends FakeAuthApi {
  final hold = Completer<void>();

  @override
  Future<AccountStanding> standing(String token, {String? userId}) async {
    calls.add('isGuest $token');
    await hold.future;
    return super.standing(token, userId: userId);
  }
}

/// A session store holding [session] as it was kept on the phone.
class _KeptSession extends SessionStore {
  _KeptSession(this.session);

  final StoredSession session;

  @override
  Future<StoredSession?> read() async => session;
}

const _key = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';
const _signinQr = 'wambito://signin?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=$_key';

void main() {
  group('reading a link', () {
    test('wambito://add and wambito://capture, nothing else', () {
      expect(launchActionOf('wambito://add'), LaunchAction.add);
      expect(launchActionOf('wambito://capture'), LaunchAction.capture);
      expect(launchActionOf('wambito://capture/'), LaunchAction.capture);
      expect(launchActionOf('wambito://due'), LaunchAction.due);
      expect(launchActionOf('wambito://progress'), LaunchAction.progress);
      expect(launchActionOf('wambito://home'), LaunchAction.home);
      expect(launchActionOf('wambito://settings'), isNull);
      expect(launchActionOf('https://add'), isNull);
      expect(launchActionOf('https://app.wambito.com/auth/verify?code=1'), isNull);
      expect(launchActionOf(''), isNull);
      expect(launchActionOf(null), isNull);
    });

    test('wambito://review, with at most one id after it', () {
      expect(launchActionOf('wambito://review'), LaunchAction.review);
      expect(launchActionOf('wambito://review/'), LaunchAction.review);
      expect(launchActionOf('wambito://review/abc-1'), LaunchAction.review);
      expect(launchReviewIdOf('wambito://review/abc-1'), 'abc-1');
      expect(launchReviewIdOf('wambito://review'), isNull);
      expect(launchActionOf('wambito://review/a/b'), isNull);
      expect(launchActionOf('wambito://due/abc'), isNull);
    });

    test('wambito://signin with the QR\'s id and key, nothing else', () {
      expect(launchActionOf(_signinQr), LaunchAction.signin);
      expect(launchSigninQrOf(_signinQr), _signinQr);
      expect(launchActionOf('wambito://signin'), LaunchAction.signin);
      for (final other in [
        'wambito://signin',
        'wambito://signin?id=0a1b2c3d-0000-4000-8000-0123456789ab',
        '$_signinQr&x=1',
        'wambito://signin/x?id=1',
        'wambito://pair?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=$_key',
        'https://app.wambito.com/signin?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=$_key',
        null,
      ]) {
        expect(launchSigninQrOf(other), isNull, reason: other);
      }
    });

    test('a link in another scheme is not a launch link', () {
      expect(launchActionOf('other://add'), isNull);
      expect(launchActionOf('other://capture'), isNull);
      expect(launchActionOf('other://due'), isNull);
    });

    test('the links the app builds say wambito://', () {
      for (final action in LaunchAction.values) {
        final link = launchLinkOf(action);
        expect(link.scheme, 'wambito');
        expect(launchActionOf(link.toString()), action);
      }
      expect(launchLinkOf(LaunchAction.capture).toString(), 'wambito://capture');
    });
  });

  testWidgets('wambito://review/<id> at a cold start opens that one once the session has loaded', (
    tester,
  ) async {
    final home = FakeHomeRepository(
      items: [detected('d1', '2026-10-21', -1000, name: 'Cafe Juan')],
    );
    final env = await pumpSettingsApp(
      tester,
      homeRepo: home,
      overrides: [
        launchLinkSourceProvider.overrideWithValue(FakeLaunchLinks('wambito://review/d1')),
      ],
    );
    expect(env.router.state.uri.path, '/review/d1');
    expect(find.byType(AddSheet), findsOneWidget);
  });

  testWidgets('wambito://review while the app runs opens the inbox over home', (tester) async {
    final links = FakeLaunchLinks();
    final home = FakeHomeRepository(
      items: [detected('d1', '2026-10-21', -1000, name: 'Cafe Juan')],
    );
    final env = await pumpSettingsApp(
      tester,
      homeRepo: home,
      location: '/settings',
      overrides: [launchLinkSourceProvider.overrideWithValue(links)],
    );
    links.open('wambito://review');
    await tester.pumpAndSettle();
    expect(env.router.state.uri.path, '/review');
    expect(find.text('Cafe Juan'), findsOneWidget);
    expect(find.byType(AddSheet), findsNothing);
  });

  testWidgets('＋ at a cold start: the add sheet opens on home once the session has loaded', (
    tester,
  ) async {
    final env = await pumpSettingsApp(
      tester,
      overrides: [launchLinkSourceProvider.overrideWithValue(FakeLaunchLinks('wambito://add'))],
    );
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AddSheet), findsOneWidget);
    expect(env.router.state.uri.path, '/');
  });

  testWidgets('🎤 at a cold start: capture opens, listening', (tester) async {
    final engine = FakeSpeechEngine()..hold = true;
    await pumpSettingsApp(
      tester,
      settle: false,
      overrides: [
        launchLinkSourceProvider.overrideWithValue(FakeLaunchLinks('wambito://capture')),
        speechEngineProvider.overrideWithValue(engine),
      ],
    );
    expect(find.byType(CaptureSheet), findsOneWidget);
    expect(tester.widget<CaptureSheet>(find.byType(CaptureSheet)).listen, isTrue);
    expect(engine.listens, 1, reason: 'listening, not waiting for a tap');
    await engine.held!.close();
  });

  testWidgets('a link while the app runs goes back to home from any screen and opens there', (
    tester,
  ) async {
    final links = FakeLaunchLinks();
    final env = await pumpSettingsApp(
      tester,
      location: '/settings',
      overrides: [launchLinkSourceProvider.overrideWithValue(links)],
    );
    expect(find.byType(AddSheet), findsNothing);

    links.open('wambito://add');
    await tester.pumpAndSettle();
    expect(env.router.state.uri.path, '/');
    expect(find.byType(AddSheet), findsOneWidget);
  });

  testWidgets('the "Hoy vence…" notice opens home from any screen, with no sheet over it', (
    tester,
  ) async {
    final links = FakeLaunchLinks();
    final env = await pumpSettingsApp(
      tester,
      location: '/settings',
      overrides: [launchLinkSourceProvider.overrideWithValue(links)],
    );
    links.open('wambito://due');
    await tester.pumpAndSettle();
    expect(env.router.state.uri.path, '/');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AddSheet), findsNothing);
    expect(find.byType(CaptureSheet), findsNothing);
  });

  testWidgets('the notice at a cold start opens home, and a sheet already open gives way', (
    tester,
  ) async {
    final links = FakeLaunchLinks();
    await pumpSettingsApp(tester, overrides: [launchLinkSourceProvider.overrideWithValue(links)]);
    links.open('wambito://add');
    await tester.pumpAndSettle();
    expect(find.byType(AddSheet), findsOneWidget);

    links.open('wambito://due');
    await tester.pumpAndSettle();
    expect(find.byType(AddSheet), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the notice brings a home that was already loaded up to date', (tester) async {
    final links = FakeLaunchLinks();
    final env = await pumpSettingsApp(
      tester,
      overrides: [launchLinkSourceProvider.overrideWithValue(links)],
    );
    final repo = env.container.read(homeRepositoryProvider) as FakeHomeRepository;
    final before = repo.calls.where((c) => c.startsWith('summary')).length;
    links.open('wambito://due');
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('summary')).length, before + 1);
  });

  for (final link in ['wambito://due', 'wambito://home']) {
    testWidgets('$link opens the current month, even from home left on an earlier one', (
      tester,
    ) async {
      final links = FakeLaunchLinks();
      final repo = FakeHomeRepository(
        items: [
          tx('now', '2026-10-22', -1000, name: 'Hoy vence'),
          tx('sep', '2026-09-15', -5000, name: 'Zapatos'),
        ],
      );
      await pumpSettingsApp(
        tester,
        homeRepo: repo,
        overrides: [
          launchLinkSourceProvider.overrideWithValue(links),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 22, 15)),
        ],
      );
      await tester.tap(findIcon(LkIconName.chevronLeft));
      await tester.pumpAndSettle();
      expect(find.text('Septiembre'), findsOneWidget);
      expect(find.text('Zapatos'), findsOneWidget);

      links.open(link);
      await tester.pumpAndSettle();
      expect(find.text('Octubre'), findsOneWidget);
      expect(find.text('Hoy vence'), findsOneWidget);
      expect(find.text('Zapatos'), findsNothing);
    });
  }

  testWidgets('the guest warning opens Guarda tu progreso, over home', (tester) async {
    final links = FakeLaunchLinks();
    final env = await pumpSettingsApp(
      tester,
      guest: true,
      location: '/settings',
      overrides: [launchLinkSourceProvider.overrideWithValue(links)],
    );
    links.open('wambito://progress');
    await tester.pumpAndSettle();
    expect(env.router.state.uri.path, '/progress');
    expect(find.byType(ProgressScreen), findsOneWidget);
    // Back is home.
    env.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('once the account has an email, the guest warning just opens home', (tester) async {
    final links = FakeLaunchLinks();
    final env = await pumpSettingsApp(
      tester,
      overrides: [launchLinkSourceProvider.overrideWithValue(links)],
    );
    links.open('wambito://progress');
    await tester.pumpAndSettle();
    expect(env.router.state.uri.path, '/');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('signed out, the notice opens nothing', (tester) async {
    final links = FakeLaunchLinks('wambito://due');
    await pumpSettingsApp(
      tester,
      signedIn: false,
      overrides: [launchLinkSourceProvider.overrideWithValue(links)],
    );
    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('a second link replaces the sheet the first one opened', (tester) async {
    final links = FakeLaunchLinks('wambito://add');
    final engine = FakeSpeechEngine()..hold = true;
    await pumpSettingsApp(
      tester,
      overrides: [
        launchLinkSourceProvider.overrideWithValue(links),
        speechEngineProvider.overrideWithValue(engine),
      ],
    );
    expect(find.byType(AddSheet), findsOneWidget);

    links.open('wambito://capture');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AddSheet), findsNothing);
    expect(find.byType(CaptureSheet), findsOneWidget);
    expect(engine.listens, 1);
    await engine.held!.close();
  });

  group('an add sheet with the person\'s input in it is kept', () {
    Future<FakeLaunchLinks> typedInSheet(WidgetTester tester, FakeSpeechEngine engine) async {
      final links = FakeLaunchLinks('wambito://add');
      await pumpSettingsApp(
        tester,
        overrides: [
          launchLinkSourceProvider.overrideWithValue(links),
          speechEngineProvider.overrideWithValue(engine),
        ],
      );
      expect(find.byType(AddSheet), findsOneWidget);
      await tester.tap(find.byKey(const Key('keypad.4')));
      await tester.tap(find.byKey(const Key('keypad.2')));
      await tester.pumpAndSettle();
      return links;
    }

    for (final link in [
      'wambito://capture',
      'wambito://add',
      'wambito://due',
      'wambito://progress',
    ]) {
      testWidgets('$link leaves it as it is', (tester) async {
        final engine = FakeSpeechEngine()..hold = true;
        final links = await typedInSheet(tester, engine);
        final typed = find.descendant(
          of: find.byType(AddSheet),
          matching: find.textContaining('42'),
        );
        expect(typed, findsWidgets);

        links.open(link);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(AddSheet), findsOneWidget);
        expect(typed, findsWidgets, reason: 'what was typed is still there');
        expect(find.byType(CaptureSheet), findsNothing);
        expect(find.byType(ProgressScreen), findsNothing);
        expect(engine.listens, 0, reason: 'the microphone never opened');
      });
    }

    testWidgets('once it closes, the next link opens again', (tester) async {
      final engine = FakeSpeechEngine()..hold = true;
      final links = await typedInSheet(tester, engine);
      Navigator.of(tester.element(find.byType(AddSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AddSheet), findsNothing);

      links.open('wambito://capture');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CaptureSheet), findsOneWidget);
      await engine.held!.close();
    });
  });

  testWidgets('signed out, a link lands on the entry screen and opens nothing', (tester) async {
    final links = FakeLaunchLinks('wambito://capture');
    final env = await pumpSettingsApp(
      tester,
      signedIn: false,
      overrides: [launchLinkSourceProvider.overrideWithValue(links)],
    );
    expect(find.byType(EntryScreen), findsOneWidget);
    expect(find.byType(CaptureSheet), findsNothing);

    links.open('wambito://add');
    await tester.pumpAndSettle();
    expect(find.byType(EntryScreen), findsOneWidget);
    expect(find.byType(AddSheet), findsNothing);
    expect(env.container.read(routerProvider).state.uri.path, '/entry');
  });

  testWidgets('a link that is not one of the two does nothing', (tester) async {
    final links = FakeLaunchLinks('wambito://somewhere');
    await pumpSettingsApp(tester, overrides: [launchLinkSourceProvider.overrideWithValue(links)]);
    links.open('https://example.com/add');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AddSheet), findsNothing);
    expect(find.byType(CaptureSheet), findsNothing);
  });

  group('a tap on the widget itself (not its buttons)', () {
    // What Glance puts on the intent of a body tap: `dat=glance-action:/CALLBACK?...`, found on the
    // emulator. Flutter hands an intent's data to the router as a location when deep linking is on.
    const glanceTap =
        'glance-action:/CALLBACK?appWidgetId=5&viewId=2131296449&viewSize=110.09524.dp%20x%2040.0.dp&extraData=0';

    testWidgets('wambito://home opens home from any screen, with no sheet over it', (tester) async {
      final links = FakeLaunchLinks();
      final env = await pumpSettingsApp(
        tester,
        location: '/settings',
        overrides: [launchLinkSourceProvider.overrideWithValue(links)],
      );
      links.open('wambito://home');
      await tester.pumpAndSettle();
      expect(env.router.state.uri.path, '/');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AddSheet), findsNothing);
    });

    testWidgets('wambito://home brings a home that was already loaded up to date', (tester) async {
      final links = FakeLaunchLinks();
      final env = await pumpSettingsApp(
        tester,
        overrides: [launchLinkSourceProvider.overrideWithValue(links)],
      );
      final repo = env.container.read(homeRepositoryProvider) as FakeHomeRepository;
      final before = repo.calls.where((c) => c.startsWith('summary')).length;
      links.open('wambito://home');
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('summary')).length, before + 1);
    });

    testWidgets('a location no route matches lands on home, not on "Page Not Found"', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings');
      // The engine's `pushRouteInformation`, as the running activity's onNewIntent sends it.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          const MethodCall('pushRouteInformation', {'location': glanceTap}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(env.router.state.uri.path, '/');
      expect(find.textContaining('glance-action'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the same at a cold start: the first route is home', (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = glanceTap;
      addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
      await pumpSettingsApp(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.textContaining('glance-action'), findsNothing);
    });
  });

  group('a cold start waits for the welcome only when the phone does not know how it stands', () {
    testWidgets(
      'a session known to be onboarded opens the link at once, even if the server hangs',
      (tester) async {
        final auth = _HangingProfile();
        await pumpSettingsApp(
          tester,
          auth: auth,
          settle: false,
          overrides: [
            sessionStoreProvider.overrideWithValue(
              _KeptSession(const StoredSession(token: 'email-token-0', guest: false)),
            ),
            launchLinkSourceProvider.overrideWithValue(FakeLaunchLinks('wambito://add')),
          ],
        );
        // Two seconds of frames, less than the wait there would be: the sheet is already open.
        expect(find.byType(AddSheet), findsOneWidget);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets('a session that does not know waits for the server, three seconds at most', (
      tester,
    ) async {
      final auth = _HangingProfile();
      await pumpSettingsApp(
        tester,
        auth: auth,
        settle: false,
        overrides: [
          sessionStoreProvider.overrideWithValue(
            _KeptSession(
              const StoredSession(token: 'email-token-0', guest: false, onboardingKnown: false),
            ),
          ),
          launchLinkSourceProvider.overrideWithValue(FakeLaunchLinks('wambito://add')),
        ],
      );
      // Still waiting after two seconds of frames...
      expect(find.byType(AddSheet), findsNothing);
      // ...and past the three seconds it opens, the server still silent.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(AddSheet), findsOneWidget);
    });

    testWidgets('a session that does not know, asked in time, is dropped if the welcome is to do', (
      tester,
    ) async {
      final auth = FakeAuthApi()..pendingOnboarding['email-token-0'] = true;
      final env = await pumpSettingsApp(
        tester,
        auth: auth,
        overrides: [
          sessionStoreProvider.overrideWithValue(
            _KeptSession(
              const StoredSession(token: 'email-token-0', guest: false, onboardingKnown: false),
            ),
          ),
          launchLinkSourceProvider.overrideWithValue(FakeLaunchLinks('wambito://add')),
        ],
      );
      expect(env.router.state.uri.path, '/welcome');
      expect(find.byType(AddSheet), findsNothing);
    });

    testWidgets('a session known to be at the welcome drops the link at once', (tester) async {
      final auth = _HangingProfile();
      final env = await pumpSettingsApp(
        tester,
        auth: auth,
        settle: false,
        overrides: [
          sessionStoreProvider.overrideWithValue(
            _KeptSession(
              const StoredSession(token: 'email-token-0', guest: false, onboardingPending: true),
            ),
          ),
          launchLinkSourceProvider.overrideWithValue(FakeLaunchLinks('wambito://add')),
        ],
      );
      expect(env.router.state.uri.path, '/welcome');
      expect(find.byType(AddSheet), findsNothing);
    });
  });

  group('a web sign-in QR the system camera opened', () {
    testWidgets(
      'wambito://signin?id=…&key=… opens the approval when the vault is open and is dropped otherwise',
      (tester) async {
        // open: the approval, with the QR looked up at once
        final security = FakeSecurity()
          ..findSignin = ({code, qr, fromLink = false}) => Completer<Never>().future;
        final links = FakeLaunchLinks();
        final env = await pumpSettingsApp(
          tester,
          location: '/settings',
          overrides: [
            launchLinkSourceProvider.overrideWithValue(links),
            securityApiProvider.overrideWithValue(security),
          ],
        );
        links.open(_signinQr);
        await tester.pumpAndSettle();
        expect(env.router.state.uri.path, '/settings/signin');
        expect(find.byType(ApproveSigninScreen), findsOneWidget);
        // a QR from a link is unauthenticated intent: the screen asks for the number
        expect(security.calls, contains('findSigninRequest code=null qr=$_signinQr fromLink'));
        // Back is home.
        env.router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets('a link during an open approval is ignored', (tester) async {
      final security = FakeSecurity()
        ..findSignin = ({code, qr, fromLink = false}) => Completer<Never>().future;
      final links = FakeLaunchLinks();
      final env = await pumpSettingsApp(
        tester,
        location: '/settings',
        overrides: [
          launchLinkSourceProvider.overrideWithValue(links),
          securityApiProvider.overrideWithValue(security),
        ],
      );
      links.open(_signinQr);
      await tester.pumpAndSettle();
      expect(find.byType(ApproveSigninScreen), findsOneWidget);
      // another request arrives while the first one is on screen: dropped, the screen stays
      const other = 'wambito://signin?id=0a1b2c3d-0000-4000-8000-0123456789ff&key=$_key';
      links.open(other);
      await tester.pumpAndSettle();
      expect(find.byType(ApproveSigninScreen), findsOneWidget);
      expect(env.router.state.uri.queryParameters['qr'], _signinQr);
      expect(security.calls.where((c) => c.contains('0123456789ff')), isEmpty);
    });

    testWidgets('two links back to back open one approval: the second is dropped', (tester) async {
      final security = FakeSecurity()
        ..findSignin = ({code, qr, fromLink = false}) => Completer<Never>().future;
      final links = FakeLaunchLinks();
      final env = await pumpSettingsApp(
        tester,
        location: '/settings',
        overrides: [
          launchLinkSourceProvider.overrideWithValue(links),
          securityApiProvider.overrideWithValue(security),
        ],
      );
      const other = 'wambito://signin?id=0a1b2c3d-0000-4000-8000-0123456789ff&key=$_key';
      // Both arrive before the first approval screen is up.
      links
        ..open(_signinQr)
        ..open(other);
      await tester.pumpAndSettle();
      expect(find.byType(ApproveSigninScreen), findsOneWidget);
      expect(env.router.state.uri.queryParameters['qr'], _signinQr);
      expect(security.calls.where((c) => c.contains('0123456789ff')), isEmpty);
      // Once that one is gone, a later link opens again.
      env.router.pop();
      await tester.pumpAndSettle();
      links.open(other);
      await tester.pumpAndSettle();
      expect(env.router.state.uri.queryParameters['qr'], other);
    });

    testWidgets('a locked vault drops it, and so does a link that is not a QR', (tester) async {
      final security = FakeSecurity();
      final links = FakeLaunchLinks();
      final env = await pumpSettingsApp(
        tester,
        location: '/settings',
        overrides: [
          launchLinkSourceProvider.overrideWithValue(links),
          securityApiProvider.overrideWithValue(null),
        ],
      );
      links.open(_signinQr);
      await tester.pumpAndSettle();
      expect(env.router.state.uri.path, '/settings');
      expect(find.byType(ApproveSigninScreen), findsNothing);
      expect(security.calls, isEmpty);
    });

    testWidgets('a malformed sign-in link is dropped with the vault open', (tester) async {
      final security = FakeSecurity();
      final links = FakeLaunchLinks();
      final env = await pumpSettingsApp(
        tester,
        location: '/settings',
        overrides: [
          launchLinkSourceProvider.overrideWithValue(links),
          securityApiProvider.overrideWithValue(security),
        ],
      );
      links.open('wambito://signin?id=nope');
      await tester.pumpAndSettle();
      expect(env.router.state.uri.path, '/settings');
      expect(security.calls, isEmpty);
    });

    testWidgets('a plain account ignores a signin link', (tester) async {
      // the harness's account is `plain`: no vault, no approval
      final links = FakeLaunchLinks(_signinQr);
      final env = await pumpSettingsApp(
        tester,
        location: '/settings',
        overrides: [launchLinkSourceProvider.overrideWithValue(links)],
      );
      await tester.pumpAndSettle();
      expect(env.router.state.uri.path, '/settings');
      expect(find.byType(ApproveSigninScreen), findsNothing);
    });
  });
}
