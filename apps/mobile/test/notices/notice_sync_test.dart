import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/device.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_controller.dart' show clockProvider;
import 'package:wambito/local/backend.dart';
import 'package:wambito/local/memory_store.dart';
import 'package:wambito/local/vault_session.dart' show VaultSession;
import 'package:wambito/vault/vault_gate.dart';
import 'package:wambito/vault/vault_providers.dart';
import 'package:wambito/notices/notice_backend.dart';
import 'package:wambito/notices/notice_platform.dart';
import 'package:wambito/notices/notice_prompt.dart';
import 'package:wambito/notices/notice_sync.dart';
import 'package:wambito/settings/preferences.dart';
import 'package:wambito/settings/security/security_api.dart' show securityApiProvider;

import '../settings/harness.dart';
import '../support/preview_account.dart';
import 'fakes.dart';

/// The permission prompt in memory: what it was asked for, and what the person answers.
class FakePrompt {
  final reasons = <NoticeReason>[];

  /// True: "Permitir"; false: "Ahora no"; null: no screen to ask on.
  bool? answer = true;

  Future<bool?> call(NoticeReason reason) async {
    reasons.add(reason);
    return answer;
  }
}

class Env {
  Env(this.settings, this.platform, this.backend, this.prompt);

  final SettingsEnv settings;
  final FakeNoticePlatform platform;
  final FakeNoticeBackend backend;
  final FakePrompt prompt;

  ProviderContainer get container => settings.container;

  Future<void> idle() => container.read(noticeSyncProvider).idle;
}

Future<Env> _pump(
  WidgetTester tester, {
  bool guest = false,
  bool signedIn = true,
  Locale locale = const Locale('es'),
  String? location,
  FakeNoticePlatform? platform,
  FakeNoticeBackend? backend,
  FakePrompt? prompt,
  List<Override> overrides = const [],
}) async {
  final fakePlatform = platform ?? FakeNoticePlatform();
  final fakeBackend = backend ?? FakeNoticeBackend();
  final fakePrompt = prompt ?? FakePrompt();
  final env = await pumpSettingsApp(
    tester,
    guest: guest,
    signedIn: signedIn,
    locale: locale,
    location: location,
    overrides: [
      noticePlatformProvider.overrideWithValue(fakePlatform),
      noticeBackendProvider.overrideWithValue(fakeBackend),
      noticePromptProvider.overrideWithValue(fakePrompt.call),
      ...overrides,
    ],
  );
  final result = Env(env, fakePlatform, fakeBackend, fakePrompt);
  await result.idle();
  await tester.pumpAndSettle();
  return result;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Notifications already allowed on the phone.
FakeNoticePlatform allowed() => FakeNoticePlatform(permissionState: NoticePermission.granted);

/// An account with a recurring payment still running: the case "Hoy vence…" is scheduled for.
FakeNoticeBackend withRule({String timezone = 'America/Bogota'}) =>
    FakeNoticeBackend(timezone: timezone, hasRecurring: true);

/// The open vault of a `preview` account for the notices: its backend, and the commits it announces.
class _Vault implements VaultSession {
  _Vault(this.backend);

  @override
  final LocalBackend backend;
  final listeners = <void Function()>[];

  @override
  String get userId => 'user-1';

  @override
  void Function() subscribe(void Function() listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  /// A commit to the vault.
  void commit() {
    for (final l in [...listeners]) {
      l();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _now = DateTime.utc(2026, 10, 28, 15);

/// A vault of account `user-1` with rent due on the 30th and a gym fee on the 3rd.
Future<(LocalBackend, Future<void> Function(String))> _vaultBackend() async {
  final backend = createLocalBackend(
    store: createMemoryStore(),
    now: () => _now,
    timezone: 'America/Bogota',
    profile: const LocalProfile(id: 'user-1', encryption: 'preview'),
  );
  Future<Map<Object?, Object?>> call(String method, String path, [Object? body]) async {
    final res = await backend.handle(method, path, const {}, body);
    return ((res!.body ?? const {}) as Map).cast<Object?, Object?>();
  }

  await call('PATCH', '/v1/me', {
    'currency': 'COP',
    'locale': 'es',
    'timezone': 'America/Bogota',
    'onboardingCompleted': true,
  });
  final food =
      (await call('POST', '/v1/categories', {
            'name': 'Food',
            'kind': 'expense',
            'icon': 'fork',
            'color': '#f90',
          }))['id']!
          as String;
  final ids = <String, String>{};
  for (final (name, day) in [('Arriendo', 30), ('Gym', 3)]) {
    ids[name] =
        (await call('POST', '/v1/recurrences', {
              'name': name,
              'amount': -50000000,
              'categoryId': food,
              'frequency': 'monthly',
              'dayOfMonth': day,
              'startDate': '2026-09-01',
            }))['id']!
            as String;
  }
  return (backend, (String name) => call('DELETE', '/v1/recurrences/${ids[name]}'));
}

/// A `preview` account whose vault is open (answering from [vault]).
List<Override> _previewWith(_Vault vault) => [
  previewAccount(),
  vaultGateStateProvider.overrideWithValue(Ready<VaultSession>(vault)),
  vaultSessionProvider.overrideWithValue(vault),
  // Settings' Security card would read the keys from the network: not what these tests are about.
  securityApiProvider.overrideWithValue(null),
  clockProvider.overrideWithValue(() => _now),
];

void main() {
  group('a preview account (its payments live only in the vault on the phone)', () {
    testWidgets(
      'with the vault locked, the list is left as it was and the server is asked nothing',
      (tester) async {
        final env = await _pump(
          tester,
          platform: allowed(),
          backend: withRule(),
          overrides: previewOpen(),
        );
        expect(env.backend.calls, 0);
        expect(env.platform.callsNamed('scheduleDue'), isEmpty);
        expect(env.platform.callsNamed('scheduleDueList'), isEmpty);
        expect(env.platform.callsNamed('cancelDue'), isEmpty);
        expect(env.prompt.reasons, isEmpty);
      },
    );

    testWidgets('the list from the vault goes to the phone, never scheduleDue, never the server', (
      tester,
    ) async {
      final (backend, _) = await _vaultBackend();
      final env = await _pump(
        tester,
        platform: allowed(),
        backend: withRule(),
        overrides: _previewWith(_Vault(backend)),
      );
      expect(env.backend.calls, 0);
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);
      expect(env.platform.callsNamed('scheduleDueList').toSet(), {
        'scheduleDueList America/Bogota es user-1',
      });
      expect(
        [for (final d in env.platform.dueLists.last) d.toJson()],
        [
          {
            'date': '2026-10-30',
            'names': ['Arriendo'],
          },
          {
            'date': '2026-11-03',
            'names': ['Gym'],
          },
        ],
      );
    });

    testWidgets('after a local write that deletes the rule, the next list lacks it', (
      tester,
    ) async {
      final (backend, delete) = await _vaultBackend();
      final vault = _Vault(backend);
      final env = await _pump(
        tester,
        platform: allowed(),
        backend: withRule(),
        overrides: _previewWith(vault),
      );
      await delete('Arriendo');
      vault.commit();
      await env.idle();
      // The widget's own wait after a commit, which runs out.
      await tester.pump(const Duration(seconds: 3));
      expect(env.platform.dueLists.length, greaterThan(1));
      expect(env.platform.dueLists.last.expand((d) => d.names), ['Gym']);
    });

    testWidgets('the switch off cancels it', (tester) async {
      final (backend, _) = await _vaultBackend();
      final env = await _pump(
        tester,
        platform: allowed(),
        location: '/settings',
        overrides: _previewWith(_Vault(backend)),
      );
      env.platform.clear();
      await _tap(tester, 'settings.dueNotice');
      await env.idle();
      expect(env.platform.callsNamed('cancelDue'), isNotEmpty);
      expect(env.platform.callsNamed('scheduleDueList'), isEmpty);
    });

    testWidgets('a guest on a preview account is not asked either', (tester) async {
      final env = await _pump(
        tester,
        guest: true,
        platform: allowed(),
        backend: withRule(),
        overrides: previewOpen(),
      );
      expect(env.backend.calls, 0);
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);
      expect(env.platform.callsNamed('scheduleGuest'), isEmpty);
    });
  });

  group('Hoy vence… at 9:00', () {
    testWidgets('it is scheduled for the profile\'s zone, in the app\'s language, for someone with a recurring payment who allowed notices', (
      tester,
    ) async {
      final env = await _pump(tester, platform: allowed(), backend: withRule());
      expect(env.platform.callsNamed('scheduleDue'), ['scheduleDue America/Bogota es']);
    });

    testWidgets('English when the phone is in English', (tester) async {
      final env = await _pump(
        tester,
        platform: allowed(),
        backend: withRule(),
        locale: const Locale('en'),
        overrides: [
          deviceHintsProvider.overrideWithValue(
            const DeviceHints(timezone: 'America/Bogota', locale: 'en-US'),
          ),
        ],
      );
      expect(env.platform.callsNamed('scheduleDue'), ['scheduleDue America/Bogota en']);
    });

    testWidgets('the zone is the profile\'s: the server\'s answer, not the phone\'s', (tester) async {
      final env = await _pump(tester, platform: allowed(), backend: withRule(timezone: 'Asia/Tokyo'));
      expect(env.platform.callsNamed('scheduleDue'), ['scheduleDue Asia/Tokyo es']);
    });

    testWidgets('a guest with a recurring payment is scheduled too', (tester) async {
      final env = await _pump(tester, guest: true, platform: allowed(), backend: withRule());
      expect(env.platform.callsNamed('scheduleDue'), hasLength(1));
    });

    testWidgets('no recurring payment, no job: it is cancelled, and never wakes the phone for nothing', (
      tester,
    ) async {
      final env = await _pump(tester, platform: allowed(), backend: FakeNoticeBackend());
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);
      expect(env.platform.callsNamed('cancelDue'), isNotEmpty);
    });

    for (final state in [NoticePermission.askable, NoticePermission.blocked]) {
      testWidgets('without the notification permission ($state) there is no job either', (tester) async {
        final env = await _pump(
          tester,
          platform: FakeNoticePlatform(permissionState: state, systemAnswer: false),
          backend: withRule(),
        );
        expect(env.platform.callsNamed('scheduleDue'), isEmpty);
        expect(env.platform.callsNamed('cancelDue'), isNotEmpty);
      });
    }

    testWidgets('once the person allows the notices, the job is scheduled', (tester) async {
      final env = await _pump(tester, platform: FakeNoticePlatform(), backend: withRule());
      expect(env.prompt.reasons, [NoticeReason.due]);
      expect(env.platform.callsNamed('requestPermission'), hasLength(1));
      expect(env.platform.callsNamed('scheduleDue'), ['scheduleDue America/Bogota es']);
    });

    testWidgets('without an answer from the server the job is left as it is: neither scheduled nor cancelled', (
      tester,
    ) async {
      final env = await _pump(
        tester,
        platform: allowed(),
        backend: FakeNoticeBackend(hasRecurring: true)..failure = Exception('offline'),
      );
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);
      expect(env.platform.callsNamed('cancelDue'), isEmpty);
    });

    testWidgets('the switch in settings stops it, and turning it on again brings it back', (tester) async {
      final env = await _pump(tester, platform: allowed(), backend: withRule(), location: '/settings');
      env.platform.clear();

      await _tap(tester, 'settings.dueNotice');
      expect(env.container.read(dueNoticeEnabledProvider), isFalse);
      await env.idle();
      expect(env.platform.callsNamed('cancelDue'), ['cancelDue']);
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);

      env.platform.clear();
      await _tap(tester, 'settings.dueNotice');
      await env.idle();
      expect(env.platform.callsNamed('scheduleDue'), ['scheduleDue America/Bogota es']);
      expect(env.platform.callsNamed('cancelDue'), isEmpty);
    });

    testWidgets('a switch turned off before the app starts is respected: nothing is scheduled', (tester) async {
      final env = await _pump(
        tester,
        overrides: [dueNoticeEnabledProvider.overrideWith(_DueOff.new)],
      );
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);
      expect(env.platform.callsNamed('cancelDue'), isNotEmpty);
    });

    testWidgets('signing out cancels both notices', (tester) async {
      final env = await _pump(tester, platform: allowed(), backend: withRule());
      env.platform.clear();
      await env.container.read(sessionProvider.notifier).signOut();
      await env.idle();
      expect(env.platform.calls, containsAll(['cancelDue', 'cancelGuest']));
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);
    });

    testWidgets('signed out at the start, nothing is scheduled', (tester) async {
      final env = await _pump(tester, signedIn: false);
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);
      expect(env.platform.callsNamed('scheduleGuest'), isEmpty);
    });
  });

  group('the guest warning', () {
    testWidgets('a guest opening the app replaces the 45-day job, every time', (tester) async {
      final env = await _pump(tester, guest: true);
      expect(env.platform.callsNamed('scheduleGuest'), ['scheduleGuest es']);

      // Coming back to the app (from the background) is opening it again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await env.idle();
      expect(env.platform.callsNamed('scheduleGuest'), ['scheduleGuest es', 'scheduleGuest es']);
    });

    testWidgets('the 45 days restart only after the server accepted a request: an offline opening leaves the job alone', (
      tester,
    ) async {
      // Offline at the start: the server's own 60-day clock did not move, so neither does ours.
      final env = await _pump(
        tester,
        guest: true,
        backend: FakeNoticeBackend()..failure = Exception('offline'),
      );
      expect(env.platform.callsNamed('scheduleGuest'), isEmpty);
      expect(env.platform.callsNamed('cancelGuest'), isEmpty);

      // Back online, the next opening is accepted: now it restarts.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await env.idle();
      expect(env.platform.callsNamed('scheduleGuest'), ['scheduleGuest es']);
    });

    testWidgets('an opening the server accepted restarts the 45 days', (tester) async {
      final backend = FakeNoticeBackend();
      final env = await _pump(tester, guest: true, backend: backend);
      expect(backend.calls, greaterThan(0));
      expect(env.platform.callsNamed('scheduleGuest'), ['scheduleGuest es']);
    });

    testWidgets('an account with an email never gets it', (tester) async {
      final env = await _pump(tester);
      expect(env.platform.callsNamed('scheduleGuest'), isEmpty);
      expect(env.platform.callsNamed('cancelGuest'), isNotEmpty);
    });

    testWidgets('the switch in settings stops it, and turning it on again brings it back', (tester) async {
      final env = await _pump(tester, guest: true, location: '/settings');
      env.platform.clear();

      await _tap(tester, 'settings.guestNotice');
      await env.idle();
      expect(env.platform.callsNamed('cancelGuest'), ['cancelGuest']);
      expect(env.platform.callsNamed('scheduleGuest'), isEmpty);

      env.platform.clear();
      await _tap(tester, 'settings.guestNotice');
      await env.idle();
      expect(env.platform.callsNamed('scheduleGuest'), ['scheduleGuest es']);
      expect(env.platform.callsNamed('cancelGuest'), isEmpty);
    });

    testWidgets('claiming an email cancels it', (tester) async {
      final env = await _pump(tester, guest: true);
      env.platform.clear();
      final session = env.container.read(sessionProvider.notifier);
      await session.claimEmail('ana@example.com');
      await session.confirmClaim('ana@example.com', '123456');
      await env.idle();
      expect(env.platform.calls, contains('cancelGuest'));
      expect(env.platform.callsNamed('scheduleGuest'), isEmpty);
    });

    testWidgets('signing out of a guest account cancels it', (tester) async {
      final env = await _pump(tester, guest: true);
      env.platform.clear();
      await env.container.read(sessionProvider.notifier).signOut(discardGuest: true);
      await env.idle();
      expect(env.platform.calls, contains('cancelGuest'));
      expect(env.platform.callsNamed('scheduleGuest'), isEmpty);
    });
  });

  group('the notification permission', () {
    testWidgets('is asked, once, when a notice is relevant: a recurring payment and the due notice on', (
      tester,
    ) async {
      final env = await _pump(tester, backend: FakeNoticeBackend(hasRecurring: true));
      expect(env.prompt.reasons, [NoticeReason.due]);
      expect(env.platform.callsNamed('requestPermission'), ['requestPermission']);

      // The next time the app opens it is not asked again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await env.idle();
      expect(env.prompt.reasons, [NoticeReason.due]);
    });

    testWidgets('a guest account with the guest notice on is relevant too', (tester) async {
      final env = await _pump(tester, guest: true);
      expect(env.prompt.reasons, [NoticeReason.guest]);
      expect(env.platform.callsNamed('requestPermission'), hasLength(1));
    });

    testWidgets('a guest with recurring payments is asked once, with the payments\' reason first', (tester) async {
      final env = await _pump(tester, guest: true, backend: FakeNoticeBackend(hasRecurring: true));
      expect(env.prompt.reasons, [NoticeReason.due]);
    });

    testWidgets('nothing to announce, nothing asked', (tester) async {
      final env = await _pump(tester);
      expect(env.prompt.reasons, isEmpty);
      expect(env.platform.callsNamed('requestPermission'), isEmpty);
    });

    testWidgets('recurring payments with the due notice off: nothing to announce', (tester) async {
      final env = await _pump(
        tester,
        backend: FakeNoticeBackend(hasRecurring: true),
        overrides: [dueNoticeEnabledProvider.overrideWith(_DueOff.new)],
      );
      expect(env.prompt.reasons, isEmpty);
    });

    testWidgets('a guest with the guest notice off: nothing to announce', (tester) async {
      final env = await _pump(
        tester,
        guest: true,
        overrides: [guestNoticeEnabledProvider.overrideWith(_GuestOff.new)],
      );
      expect(env.prompt.reasons, isEmpty);
    });

    testWidgets('turning a notice on later, while the app is open, is when it is first relevant', (tester) async {
      final env = await _pump(
        tester,
        backend: FakeNoticeBackend(hasRecurring: true),
        location: '/settings',
        overrides: [dueNoticeEnabledProvider.overrideWith(_DueOff.new)],
      );
      expect(env.prompt.reasons, isEmpty);

      await _tap(tester, 'settings.dueNotice');
      await env.idle();
      expect(env.prompt.reasons, [NoticeReason.due]);
    });

    testWidgets('already allowed: nothing to ask', (tester) async {
      final env = await _pump(
        tester,
        platform: FakeNoticePlatform(permissionState: NoticePermission.granted),
        backend: FakeNoticeBackend(hasRecurring: true),
      );
      expect(env.prompt.reasons, isEmpty);
    });

    testWidgets('switched off in the phone\'s settings: the app cannot ask, and does not try', (tester) async {
      final env = await _pump(
        tester,
        platform: FakeNoticePlatform(permissionState: NoticePermission.blocked),
        backend: FakeNoticeBackend(hasRecurring: true),
      );
      expect(env.prompt.reasons, isEmpty);
    });

    testWidgets('refused once, never asked again; the notices are just not posted', (tester) async {
      final platform = FakeNoticePlatform(systemAnswer: false);
      final env = await _pump(tester, platform: platform, backend: FakeNoticeBackend(hasRecurring: true));
      expect(env.prompt.reasons, [NoticeReason.due]);
      expect(platform.permissionState, NoticePermission.askable);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await env.idle();
      await env.container.read(sessionProvider.notifier).signOut();
      await env.idle();
      expect(env.prompt.reasons, hasLength(1));
      expect(env.platform.callsNamed('requestPermission'), hasLength(1));
    });

    testWidgets('"Ahora no" is an answer too: Android\'s prompt is not shown, and it is not asked again', (
      tester,
    ) async {
      final prompt = FakePrompt()..answer = false;
      final env = await _pump(
        tester,
        prompt: prompt,
        backend: FakeNoticeBackend(hasRecurring: true),
      );
      expect(prompt.reasons, [NoticeReason.due]);
      expect(env.platform.callsNamed('requestPermission'), isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await env.idle();
      expect(prompt.reasons, hasLength(1));
    });

    testWidgets('no screen to ask on yet: not counted, it is asked at the next chance', (tester) async {
      final prompt = FakePrompt()..answer = null;
      final env = await _pump(tester, prompt: prompt, backend: FakeNoticeBackend(hasRecurring: true));
      expect(prompt.reasons, hasLength(1));

      prompt.answer = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await env.idle();
      expect(prompt.reasons, hasLength(2));
      expect(env.platform.callsNamed('requestPermission'), hasLength(1));
    });
  });

  group('not on Android', () {
    testWidgets('without the platform channel the notices do nothing at all, and nothing is asked', (tester) async {
      final backend = FakeNoticeBackend(hasRecurring: true);
      final platform = FakeNoticePlatform(permissionState: NoticePermission.unavailable);
      final env = await _pump(tester, platform: platform, backend: backend);
      expect(platform.calls, isEmpty);
      expect(backend.calls, 0);
      expect(env.prompt.reasons, isEmpty);
    });
  });
}

/// A switch that was turned off before the app started.
class _DueOff extends DueNoticeEnabled {
  @override
  bool get initial => false;
}

class _GuestOff extends GuestNoticeEnabled {
  @override
  bool get initial => false;
}
