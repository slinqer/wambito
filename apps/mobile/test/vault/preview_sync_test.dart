// What the phone's background jobs and the widget are told of the account's mode: the mode is
// written where Android's workers and iOS's due task read it, the widget gets no figures for a
// `preview` account, and its queued captures are forgotten once.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/device.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture_auto/capture_platform.dart';
import 'package:wambito/feedback/stored_flag.dart';
import 'package:wambito/home/home_cache.dart' show sessionOwnerOf;
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/local/vault_session.dart' show VaultProfile;
import 'package:wambito/settings/initial_settings.dart';
import 'package:wambito/settings/settings_store.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/preview_sync.dart';

import '../capture_auto/fakes.dart';
import '../home/fakes.dart';
import '../settings/fakes.dart';

class _Native implements NativeEncryptionMode {
  final writes = <String?>[];

  @override
  Future<void> write(String? mode) async => writes.add(mode);
}

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

VaultAccount _account(EncryptionMode mode) => VaultAccount(
  owner: sessionOwnerOf('t'),
  profile: const VaultProfile(
    id: 'user-1',
    email: 'ana@wambito.test',
    isAnonymous: false,
    locale: 'es',
    timezone: 'America/Bogota',
  ),
  mode: mode,
);

void main() {
  const signedIn = SessionState.signedIn(StoredSession(token: 't', guest: false));
  late _Native native;
  late FakeAutoCapturePlatform capture;
  late FakeWidgetStore widget;
  late _Session session;

  ProviderContainer make({
    SessionState initial = signedIn,
    Future<VaultAccount?> Function()? account,
  }) {
    session = _Session(initial);
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => session),
        vaultAccountProvider.overrideWith((ref) {
          ref.watch(sessionProvider.select((s) => s.stored?.token));
          return account!();
        }),
        nativeEncryptionModeProvider.overrideWithValue(native),
        autoCapturePlatformProvider.overrideWithValue(capture),
        widgetStoreProvider.overrideWithValue(widget),
        flagStoreProvider.overrideWith((ref, key) => FakeFlagStore()..value = false),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        initialSettingsProvider.overrideWithValue(
          InitialSettings(serverUrl: Uri.parse('https://x.test'), themeMode: ThemeMode.dark),
        ),
        deviceHintsProvider.overrideWithValue(
          const DeviceHints(timezone: 'America/Bogota', locale: 'es-CO'),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(sessionProvider);
    return c;
  }

  setUp(() {
    native = _Native();
    capture = FakeAutoCapturePlatform();
    widget = FakeWidgetStore();
  });

  test('preview: the jobs are told, the queue is cleared once, the widget says it waits', () async {
    final c = make(account: () => SynchronousFuture(_account(EncryptionMode.preview)));
    c.listen(previewSyncProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(native.writes.last, 'preview');
    expect(native.writes, isNot(contains('plain')));
    expect(capture.callsNamed('clearQueue'), ['clearQueue']);
    final doc = jsonDecode(widget.saved[widgetSnapshotKey]!) as Map<String, Object?>;
    expect(doc['signedIn'], false);
    expect(doc['line'], 'Próximamente con cifrado');
    expect(doc.containsKey('remaining'), isFalse);
  });

  test('plain: the jobs are told, and nothing is cleared or written to the widget', () async {
    final c = make(account: () => SynchronousFuture(_account(EncryptionMode.plain)));
    c.listen(previewSyncProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(native.writes.last, 'plain');
    expect(capture.callsNamed('clearQueue'), isEmpty);
    expect(widget.saved, isEmpty);
  });

  test('a mode not learned yet is written as unknown, then replaced by the real one', () async {
    final answer = Completer<VaultAccount?>();
    final c = make(account: () => answer.future);
    c.listen(previewSyncProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(native.writes, ['unknown']);

    answer.complete(_account(EncryptionMode.preview));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(native.writes.last, 'preview');
    expect(capture.callsNamed('clearQueue'), hasLength(1));
  });

  test(
    'signed out, the mode is cleared; while the session is still being read, nothing is',
    () async {
      final loading = make(initial: SessionState.loading, account: () => SynchronousFuture(null));
      loading.listen(previewSyncProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(native.writes, isEmpty, reason: 'a cold start never turns a preview account loose');

      native.writes.clear();
      final out = make(initial: SessionState.signedOut, account: () => SynchronousFuture(null));
      out.listen(previewSyncProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(native.writes, [null]);
    },
  );

  test('nativeModeOf: none without a session, unknown without an account, else the mode', () {
    expect(nativeModeOf(null, null), isNull);
    expect(nativeModeOf(null, EncryptionMode.preview), isNull);
    expect(nativeModeOf('o', null), 'unknown');
    expect(nativeModeOf('o', EncryptionMode.plain), 'plain');
    expect(nativeModeOf('o', EncryptionMode.preview), 'preview');
  });
}
