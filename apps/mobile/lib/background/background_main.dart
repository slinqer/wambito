import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../api/client.dart';
import '../api/device.dart';
import '../api/session.dart' show SessionStore;
import '../capture_auto/capture_platform.dart';
import '../local/keys.dart';
import '../local/sqlite_store.dart';
import '../local/vault_lock.dart';
import '../settings/initial_settings.dart';
import '../settings/settings_store.dart';
import '../vault/encryption_mode.dart' show EncryptionStore, VaultAccount;
import 'background_channel.dart';
import 'background_run.dart';
import 'queued_capture.dart';

/// How long a headless run waits for the vault's lease before it reports `busy` (the app or another
/// worker is syncing; the queue is retried, D23).
const _leaseWait = Duration(seconds: 5);

/// The body of `syncMain` (`'sync'`) and `captureMain` (`'capture'`), the entry points native code
/// starts in a headless engine (D22). It builds the real [BackgroundDeps] (D14), runs
/// [runBackground] and tells native code how it ended with `wambito/background` `finished`; an
/// error anywhere is the outcome `failed`, never an uncaught one.
///
/// The widget and due-list effects are no-ops here until their tasks (9 and 10) fill them.
Future<void> backgroundMain(String kind) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  var report = const BackgroundReport(BackgroundOutcome.failed);
  try {
    report = await _run(kind);
  } on Object {
    // `failed`, as above.
  }
  await const BackgroundChannel().finished(report);
}

Future<BackgroundReport> _run(String kind) async {
  final settings = await InitialSettings.read(const SecureSettingsStore());
  final hints = await DeviceHints.read();
  final sessions = SessionStore();
  const encryption = EncryptionStore();
  final keyStorage = KeyStorage();

  // Read once: the queue needs the account before the run asks for it again.
  final tokenFuture = sessions.read().then((s) => s?.token);
  final accounts = <String, Future<VaultAccount?>>{};
  Future<VaultAccount?> recall(String token) =>
      accounts.putIfAbsent(token, () => encryption.recall(token));

  final deps = BackgroundDeps(
    token: () => tokenFuture,
    recall: recall,
    loadKeys: (userId) => loadLocalKeys(userId, keyStorage),
    openStore: (userId) => SqliteStore.open(userId, background: true),
    network: (token) => _network(settings.serverUrl, token, hints),
    lease: (userId) => waitLease(userId, holder: 'background', wait: _leaseWait),
    now: DateTime.now,
    refreshKeys: (userId, network) async =>
        (await refreshKeys(KeysOptions(userId: userId, dio: network, storage: keyStorage))).keyring,
    dropKeyVersion: (userId, v) => dropKeyVersion(userId, v, keyStorage),
  );
  final effects = BackgroundEffects(
    widget: (userId, backend) async {},
    due: (userId, backend) async {},
  );

  var captures = const <QueuedCapture>[];
  var confirms = const <String>[];
  const platform = ChannelAutoCapturePlatform();
  if (kind == 'capture') {
    final token = await tokenFuture;
    final account = token == null ? null : await recall(token);
    if (account != null) {
      final queued = await platform.takeQueued(account.profile.id);
      captures = queued.captures;
      confirms = queued.confirms;
    }
  }
  return runBackground(
    deps,
    effects,
    captures: captures,
    confirms: confirms,
    ack: platform.ackQueued,
  );
}

/// The headless Dio (D14): the API at `<server>/api` with the bearer token and the phone's
/// headers, and `x-wambito-background: 1`, so the server never counts it as the person's activity.
Dio _network(Uri server, String token, DeviceHints hints) {
  final dio = ApiClient.forServer(server, token: token, hints: hints).dio;
  dio.options.headers['x-wambito-background'] = '1';
  return dio;
}
