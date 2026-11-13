import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/device.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/feedback/stored_flag.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/home/widget_sync.dart';
import 'package:wambito/settings/initial_settings.dart';
import 'package:wambito/settings/preferences.dart';
import 'package:wambito/settings/settings_store.dart';

import '../settings/fakes.dart';
import 'fakes.dart';
import 'fixtures.dart';

/// A session already read, which the test signs out by hand.
class _Session extends SessionController {
  _Session(this.initial);

  final SessionState initial;

  @override
  SessionState build() {
    ready = Future.value();
    refreshed = Future.value();
    return initial;
  }

  void signOutHere() => state = SessionState.signedOut;
}

/// A flag store whose first read waits for [gate] (secure storage is slow at a cold start).
class _SlowFlagStore extends FakeFlagStore {
  _SlowFlagStore(super.value);

  final gate = Completer<void>();

  @override
  Future<bool?> read() async {
    await gate.future;
    return value;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 22, 15, 30);
  const signedIn = SessionState.signedIn(StoredSession(token: 't', guest: false));

  late FakeWidgetStore store;
  late _SlowFlagStore hide;
  late _Session session;
  late ProviderContainer container;

  Map<String, Object?> doc() => jsonDecode(store.saved[widgetSnapshotKey]!) as Map<String, Object?>;

  ProviderContainer make({
    SessionState initial = signedIn,
    ThemeMode theme = ThemeMode.dark,
    Locale? locale,
    String deviceLocale = 'es-CO',
  }) {
    session = _Session(initial);
    final c = ProviderContainer(
      overrides: [
        widgetStoreProvider.overrideWithValue(store),
        sessionProvider.overrideWith(() => session),
        flagStoreProvider.overrideWith(
          (ref, key) => key == 'setting.widget.hideAmount' ? hide : FakeFlagStore(),
        ),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        initialSettingsProvider.overrideWithValue(
          InitialSettings(serverUrl: Uri.parse('https://x.test'), themeMode: theme, locale: locale),
        ),
        deviceHintsProvider.overrideWithValue(
          DeviceHints(timezone: 'America/Bogota', locale: deviceLocale),
        ),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    // The session and the hide-amount choice start loading, as they do at app start.
    c.read(sessionProvider);
    c.read(hideWidgetAmountProvider);
    // The app keeps the sync from the start (app.dart).
    c.read(widgetSyncProvider);
    return c;
  }

  setUp(() {
    store = FakeWidgetStore();
    hide = _SlowFlagStore(true);
  });

  test('a loaded summary waits for the hide-amount choice, then is written with it', () async {
    container = make();
    final written = container
        .read(widgetSyncProvider)
        .summaryLoaded(
          summary(budgetTotal: 200000000, spent: 50000000),
          currency: 'COP',
          timezone: 'America/Bogota',
        );
    await Future<void>.delayed(Duration.zero);
    expect(store.saved, isEmpty, reason: 'nothing before the choice is known');

    hide.gate.complete();
    await written;
    expect(doc(), {
      'v': 3,
      'signedIn': true,
      'remaining': 150000000,
      'spent': 50000000,
      'budgetTotal': 200000000,
      'currency': 'COP',
      'locale': 'es',
      'month': '2026-10',
      'mood': 'happy',
      'updatedAt': '2026-10-22T15:30:00.000Z',
      'hideAmount': true,
      'theme': 'dark',
      'timezone': 'America/Bogota',
    });
    expect(store.updates, greaterThanOrEqualTo(1));
  });

  test("the snapshot's language is the app's: the choice in Settings, else the phone's", () async {
    hide.gate.complete();
    container = make(locale: const Locale('en'), deviceLocale: 'es-CO');
    await container
        .read(widgetSyncProvider)
        .summaryLoaded(summary(), currency: 'COP', timezone: 'America/Bogota');
    expect(doc()['locale'], 'en');

    store = FakeWidgetStore();
    container = make(deviceLocale: 'en-US');
    await container
        .read(widgetSyncProvider)
        .summaryLoaded(summary(), currency: 'COP', timezone: 'America/Bogota');
    expect(doc()['locale'], 'en');
  });

  test(
    'turning the hide-amount switch rewrites the snapshot, figures and time unchanged',
    () async {
      hide.gate.complete();
      container = make();
      await container
          .read(widgetSyncProvider)
          .summaryLoaded(
            summary(budgetTotal: 100, spent: 20),
            currency: 'COP',
            timezone: 'America/Bogota',
          );
      final before = doc();
      final updates = store.updates;

      await container.read(hideWidgetAmountProvider.notifier).set(false);
      await container.read(widgetSyncProvider).idle;
      expect(doc(), {...before, 'hideAmount': false});
      expect(store.updates, greaterThan(updates));
    },
  );

  test('the widget follows the theme chosen in the app', () async {
    hide.gate.complete();
    container = make();
    await container
        .read(widgetSyncProvider)
        .summaryLoaded(summary(), currency: 'COP', timezone: 'America/Bogota');
    expect(doc()['theme'], 'dark');

    await container.read(themeModeProvider.notifier).set(ThemeMode.light);
    await container.read(widgetSyncProvider).idle;
    expect(doc()['theme'], 'light');

    await container.read(themeModeProvider.notifier).set(ThemeMode.system);
    await container.read(widgetSyncProvider).idle;
    expect(doc()['theme'], 'system');
  });

  group('after sign out the widget never shows the previous figure (Review Focus 4)', () {
    test(
      'signing out writes a snapshot with no figure at once, without waiting for anything',
      () async {
        container = make();
        // The hide-amount choice is still loading: sign-out does not wait for it.
        final done = container.read(widgetSyncProvider).signedOut();
        expect(doc(), {
          'v': 3,
          'signedIn': false,
          'hideAmount': false,
          'theme': 'dark',
          'locale': 'es',
        });
        await done;
        expect(store.updates, 1);
      },
    );

    test('from the sign-out on, nothing signed in is written, until someone signs in', () async {
      hide.gate.complete();
      container = make();
      final sync = container.read(widgetSyncProvider);
      // Sign-out writes the widget first, while the session still reads as signed in.
      await sync.signedOut();
      await sync.summaryLoaded(
        summary(budgetTotal: 100, spent: 20),
        currency: 'COP',
        timezone: 'America/Bogota',
      );
      await container.read(themeModeProvider.notifier).set(ThemeMode.light);
      await sync.idle;
      expect(doc()['signedIn'], false);
      expect(doc().containsKey('remaining'), isFalse);

      sync.signedIn();
      await sync.summaryLoaded(
        summary(budgetTotal: 100, spent: 20),
        currency: 'COP',
        timezone: 'America/Bogota',
      );
      expect(doc()['signedIn'], true);
    });

    test('a summary that arrives after the sign-out writes nothing', () async {
      container = make();
      final late = container
          .read(widgetSyncProvider)
          .summaryLoaded(
            summary(budgetTotal: 100, spent: 20),
            currency: 'COP',
            timezone: 'America/Bogota',
          );
      session.signOutHere();
      await container.read(widgetSyncProvider).signedOut();
      hide.gate.complete();
      await late;
      expect(doc()['signedIn'], false);
      expect(doc().containsKey('remaining'), isFalse);
    });

    test('a choice changed after the sign-out keeps the snapshot signed out', () async {
      hide.gate.complete();
      container = make();
      await container
          .read(widgetSyncProvider)
          .summaryLoaded(
            summary(budgetTotal: 100, spent: 20),
            currency: 'COP',
            timezone: 'America/Bogota',
          );
      session.signOutHere();
      await container.read(widgetSyncProvider).signedOut();
      await container.read(hideWidgetAmountProvider.notifier).set(false);
      await container.read(widgetSyncProvider).idle;
      expect(doc()['signedIn'], false);
      expect(doc().containsKey('remaining'), isFalse);
    });

    test('signed out from the start, a choice writes the signed-out snapshot', () async {
      hide.gate.complete();
      container = make(initial: SessionState.signedOut);
      await container.read(themeModeProvider.notifier).set(ThemeMode.light);
      await container.read(widgetSyncProvider).idle;
      expect(doc(), {
        'v': 3,
        'signedIn': false,
        'hideAmount': true,
        'theme': 'light',
        'locale': 'es',
      });
    });
  });

  test('an old snapshot (version 1) is replaced, never patched, by the next summary', () async {
    hide.gate.complete();
    store.saved[widgetSnapshotKey] = '{"v":1,"kind":"remaining","amount":"\$1.500.000"}';
    container = make();
    await container.read(themeModeProvider.notifier).set(ThemeMode.light);
    await container.read(widgetSyncProvider).idle;
    expect(store.saved[widgetSnapshotKey], contains('"v":1'), reason: 'nothing to patch');

    await container
        .read(widgetSyncProvider)
        .summaryLoaded(summary(), currency: 'COP', timezone: 'America/Bogota');
    expect(doc()['v'], 3);
    expect(doc().containsKey('amount'), isFalse);
  });

  test('a store that cannot be reached never breaks the app', () async {
    hide.gate.complete();
    store.failure = StateError('broken');
    container = make();
    await container
        .read(widgetSyncProvider)
        .summaryLoaded(summary(), currency: 'COP', timezone: 'America/Bogota');
    await container.read(widgetSyncProvider).signedOut();
    await container.read(hideWidgetAmountProvider.notifier).set(false);
    await container.read(widgetSyncProvider).idle;
  });
  group('a preview account (its figures live only in the vault on the phone)', () {
    test(
      'the widget gets no figures and says "Próximamente con cifrado", and nothing else is written',
      () async {
        hide.gate.complete();
        container = make();
        final sync = container.read(widgetSyncProvider);
        await sync.modeChanged(preview: true);
        await sync.idle;
        expect(doc(), {
          'v': 3,
          'signedIn': false,
          'hideAmount': true,
          'theme': 'dark',
          'locale': 'es',
          'line': 'Próximamente con cifrado',
        });

        // The month home loads comes from the vault: no figure of it reaches the widget.
        await sync.summaryLoaded(
          summary(budgetTotal: 200000000, spent: 50000000),
          currency: 'COP',
          timezone: 'America/Bogota',
        );
        expect(doc().containsKey('remaining'), isFalse);
        expect(doc().containsKey('spent'), isFalse);
        expect(doc()['line'], 'Próximamente con cifrado');
      },
    );

    test('the line is in the widget\'s language', () async {
      hide.gate.complete();
      container = make(locale: const Locale('en'));
      final sync = container.read(widgetSyncProvider);
      await sync.modeChanged(preview: true);
      await sync.idle;
      expect(doc()['line'], 'Coming soon with encryption');
      expect(doc()['locale'], 'en');
    });

    test('the hide-amount and theme choices keep the line', () async {
      hide.gate.complete();
      container = make();
      final sync = container.read(widgetSyncProvider);
      await sync.modeChanged(preview: true);
      await container.read(themeModeProvider.notifier).set(ThemeMode.light);
      await sync.idle;
      expect(doc()['theme'], 'light');
      expect(doc()['line'], 'Próximamente con cifrado');
      expect(doc()['signedIn'], isFalse);
    });

    test('signed out, the widget is the usual signed-out one with no line', () async {
      hide.gate.complete();
      container = make();
      final sync = container.read(widgetSyncProvider);
      await sync.modeChanged(preview: true);
      await sync.idle;
      await sync.signedOut();
      expect(doc().containsKey('line'), isFalse);
      expect(widgetSignedOut(store), isTrue);
    });

    test('a plain account is never touched by modeChanged', () async {
      hide.gate.complete();
      container = make();
      final sync = container.read(widgetSyncProvider);
      await sync.modeChanged(preview: false);
      await sync.idle;
      expect(store.saved, isEmpty);
      await sync.summaryLoaded(summary(), currency: 'COP', timezone: 'America/Bogota');
      expect(doc()['signedIn'], isTrue);
      expect(doc().containsKey('line'), isFalse);
    });
  });
}
