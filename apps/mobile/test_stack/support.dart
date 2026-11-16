/// Shared by the stack tests: the real dev stack's addresses, one phone (folder, in-memory key
/// storage, network, gate over the real keys) and the sign-in through Mailpit.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/device.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/keys.dart' as keys;
import 'package:wambito/local/keys.dart' show KeysOptions, LocalKeys;
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/vault_gate.dart';

const email = 'preview@wambito.test';
const userId = 'preview-e2e';
final api = Uri.parse(Platform.environment['WAMBITO_E2E_API'] ?? 'http://localhost:3000');
final mailpit = Uri.parse(Platform.environment['WAMBITO_E2E_MAILPIT'] ?? 'http://localhost:8025');

/// A key storage in memory, its own for each phone (the plugin's mock is shared by the process).
class MemoryStorage extends FlutterSecureStorage {
  MemoryStorage();

  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(values);
}

const hints = DeviceHints(timezone: 'America/Bogota', locale: 'es');

/// The code of the newest sign-in email to [email] that is not in [skip].
Future<String> readCode(Set<String> skip) async {
  final http = Dio();
  for (var i = 0; i < 30; i++) {
    final list = await http.getUri<Map<String, Object?>>(
      mailpit.replace(path: '/api/v1/messages', query: 'limit=200'),
    );
    for (final m in (list.data!['messages']! as List).cast<Map<String, Object?>>()) {
      final to = (m['To']! as List).cast<Map<String, Object?>>();
      if (skip.contains(m['ID']) ||
          !to.any((t) => (t['Address']! as String).toLowerCase() == email)) {
        continue;
      }
      final code = RegExp(r'\b(\d{6})\b').firstMatch(m['Subject']! as String)?.group(1);
      if (code != null) return code;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('no sign-in email to $email');
}

Future<Set<String>> mailIds() async {
  final list = await Dio().getUri<Map<String, Object?>>(
    mailpit.replace(path: '/api/v1/messages', query: 'limit=200'),
  );
  return {
    for (final m in (list.data!['messages']! as List).cast<Map<String, Object?>>())
      m['ID']! as String,
  };
}

/// One phone: its folder, its key storage, the network client and the gate over the real keys.
class Phone {
  Phone(this.token, this.dir) {
    network = ApiClient.forServer(
      api,
      token: token,
      hints: hints,
      clientIp: '10.77.${DateTime.now().microsecond % 250}.1',
      development: true,
    ).dio;
    options = KeysOptions(userId: userId, dio: network, storage: KeyStorage(storage));
  }

  final String token;
  final Directory dir;
  final storage = MemoryStorage();
  late final Dio network;
  late final KeysOptions options;
  VaultSession? session;

  Future<VaultGate<LocalKeys, VaultSession>> gate({required VaultProfile profile}) async {
    final gate = VaultGate<LocalKeys, VaultSession>(
      VaultGateDeps(
        userId: userId,
        loadLocalKeys: () => keys.loadLocalKeys(userId, options.storage),
        prepareAccount: () async {
          final prepared = await keys.prepareAccount(options, guest: false);
          return GatePrepared(recoveryKey: prepared.recoveryKey, commit: prepared.commit);
        },
        unlockWithRecovery: (text) => keys.unlockWithRecovery(options, text),
        open: (local, fresh) async {
          final opened = await openVaultSession(
            OpenVaultOptions(
              profile: profile,
              keys: local,
              fresh: fresh,
              network: network,
              storage: options.storage,
              syncDebounce: const Duration(milliseconds: 100),
              openStore: (id) =>
                  SqliteStore.open(id, directory: dir.path, factory: databaseFactoryFfi),
              deleteStore: (id) async {},
            ),
          );
          session = opened;
          return opened;
        },
      ),
    );
    return gate;
  }

  /// `/v1` through the vault's interceptor, as the app's screens call it.
  Dio screens() =>
      ApiClient.forServer(api, token: token, hints: hints).dio
        ..interceptors.add(session!.interceptor);
}

Future<void> until(
  VaultGate<LocalKeys, VaultSession> gate,
  bool Function(VaultGateState<VaultSession>) done,
) async {
  final completer = Completer<void>();
  void check() {
    if (done(gate.state) && !completer.isCompleted) completer.complete();
  }

  final off = gate.subscribe(check);
  check();
  try {
    await completer.future.timeout(const Duration(seconds: 60));
  } finally {
    off();
  }
}

/// The seeded preview account signs in with an email code, as the app's AuthApi does: its bearer
/// token and profile.
Future<({String token, VaultProfile profile})> signIn() async {
  final auth = HttpAuthApi(server: api, hints: hints);
  final old = await mailIds();
  await auth.sendCode(email);
  final token = await auth.verifyCode(email, await readCode(old));
  final me = (await ApiClient.forServer(
    api,
    token: token,
    hints: hints,
  ).api.getDefaultApi().getMe()).data!;
  if (me.id != userId || me.encryption.name != 'preview') {
    throw StateError('the seeded preview account is not the one signed in');
  }
  return (
    token: token,
    profile: VaultProfile(
      id: me.id,
      email: me.email,
      isAnonymous: false,
      locale: 'es',
      timezone: 'America/Bogota',
    ),
  );
}
