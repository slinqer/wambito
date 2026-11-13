@Tags(['stack'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/device.dart';
import 'package:wambito/crypto/crypto.dart' show fromBase64Url;
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/keys.dart' as keys;
import 'package:wambito/local/keys.dart' show KeysOptions, LocalKeys;
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/vault_gate.dart';

/// The phone's vault against the real dev stack (`docker compose up`: API, Postgres, Mailpit), as
/// apps/web/e2e/vault.spec.ts does for the browser: the seeded preview account
/// (preview@wambito.test, id preview-e2e; apps/mobile/scripts/run-vault-e2e.sh resets it first)
/// signs in with an email code, sets up its keys through [VaultGate], adds a movement, syncs, and a
/// second phone (an empty folder and key storage) unlocks with the recovery key and sees it. The
/// server only ever holds ciphertext: no record body decodes to the movement's name.
///
/// Plain `flutter test` with sqflite_common_ffi and an in-memory key storage; no emulator.
const _email = 'preview@wambito.test';
const _userId = 'preview-e2e';
const _name = 'almuerzo e2e';
const _amount = -1250000;
final _api = Uri.parse(Platform.environment['WAMBITO_E2E_API'] ?? 'http://localhost:3000');
final _mailpit = Uri.parse(Platform.environment['WAMBITO_E2E_MAILPIT'] ?? 'http://localhost:8025');

/// A key storage in memory, its own for each phone (the plugin's mock is shared by the process).
class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage();

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

const _hints = DeviceHints(timezone: 'America/Bogota', locale: 'es');

/// The code of the newest sign-in email to [_email] that is not in [skip].
Future<String> _readCode(Set<String> skip) async {
  final http = Dio();
  for (var i = 0; i < 30; i++) {
    final list = await http.getUri<Map<String, Object?>>(_mailpit.replace(path: '/api/v1/messages', query: 'limit=200'));
    for (final m in (list.data!['messages']! as List).cast<Map<String, Object?>>()) {
      final to = (m['To']! as List).cast<Map<String, Object?>>();
      if (skip.contains(m['ID']) || !to.any((t) => (t['Address']! as String).toLowerCase() == _email)) continue;
      final code = RegExp(r'\b(\d{6})\b').firstMatch(m['Subject']! as String)?.group(1);
      if (code != null) return code;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('no sign-in email to $_email');
}

Future<Set<String>> _mailIds() async {
  final list = await Dio().getUri<Map<String, Object?>>(_mailpit.replace(path: '/api/v1/messages', query: 'limit=200'));
  return {for (final m in (list.data!['messages']! as List).cast<Map<String, Object?>>()) m['ID']! as String};
}

/// One phone: its folder, its key storage, the network client and the gate over the real keys.
class _Phone {
  _Phone(this.token, this.dir) {
    network = ApiClient.forServer(_api, token: token, hints: _hints, clientIp: '10.77.${DateTime.now().microsecond % 250}.1', development: true).dio;
    options = KeysOptions(userId: _userId, dio: network, storage: KeyStorage(storage));
  }

  final String token;
  final Directory dir;
  final storage = _MemoryStorage();
  late final Dio network;
  late final KeysOptions options;
  VaultSession? session;

  Future<VaultGate<LocalKeys, VaultSession>> gate({required VaultProfile profile}) async {
    final gate = VaultGate<LocalKeys, VaultSession>(
      VaultGateDeps(
        userId: _userId,
        loadLocalKeys: () => keys.loadLocalKeys(_userId, options.storage),
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
              openStore: (id) => SqliteStore.open(id, directory: dir.path, factory: databaseFactoryFfi),
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
  Dio screens() => ApiClient.forServer(_api, token: token, hints: _hints).dio..interceptors.add(session!.interceptor);
}

Future<void> _until(VaultGate<LocalKeys, VaultSession> gate, bool Function(VaultGateState<VaultSession>) done) async {
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

void main() {
  sqfliteFfiInit();
  late Directory root;
  setUpAll(() => root = Directory.systemTemp.createTempSync('wambito-vault-e2e'));
  tearDownAll(() => root.deleteSync(recursive: true));

  test('a preview account sets up, syncs, and a second phone unlocks it with the recovery key', () async {
    // 1. Sign in with the email code, as the app's AuthApi does.
    final auth = HttpAuthApi(server: _api, hints: _hints);
    final old = await _mailIds();
    await auth.sendCode(_email);
    final token = await auth.verifyCode(_email, await _readCode(old));
    final me = (await ApiClient.forServer(_api, token: token, hints: _hints).api.getDefaultApi().getMe()).data!;
    expect(me.id, _userId);
    expect(me.encryption.name, 'preview');
    final profile = VaultProfile(id: me.id, email: me.email, isAnonymous: false, locale: 'es', timezone: 'America/Bogota');

    // 2. Set up the account through the gate; keep the recovery key.
    final first = _Phone(token, Directory('${root.path}/first')..createSync());
    final gate = await first.gate(profile: profile);
    gate.start();
    await _until(gate, (s) => s is Setup || s is Ready);
    final setup = gate.state;
    expect(setup, isA<Setup<VaultSession>>());
    final recoveryKey = (setup as Setup<VaultSession>).recoveryKey;
    await gate.confirmSetup();
    await _until(gate, (s) => s is Ready || s is Locked);
    expect(gate.state, isA<Ready<VaultSession>>());

    // 3. A movement through the interceptor.
    final screens = first.screens();
    final categories = (await screens.get<Object?>('/v1/categories')).data;
    final list = categories is Map ? categories['items'] as List : categories! as List;
    final category = (list.cast<Map<Object?, Object?>>().firstWhere((c) => c['kind'] == 'expense'))['id'];
    final created = await screens.post<Map<Object?, Object?>>(
      '/v1/transactions',
      data: {'name': _name, 'amount': _amount, 'categoryId': category, 'date': '2026-10-21'},
    );
    expect(created.statusCode, inInclusiveRange(200, 299));

    // 4. Sync.
    final result = await first.session!.sync();
    expect(result.problem, isNull);

    // 5. The server holds ciphertext only.
    final raw = await first.network.get<Map<String, Object?>>('/v2/sync', queryParameters: {'since': 0, 'limit': 1000});
    final records = (raw.data!['records']! as List).cast<Map<String, Object?>>();
    expect(records, isNotEmpty);
    for (final r in records) {
      final body = r['body'] as String?;
      if (body == null) continue;
      expect(utf8.decode(fromBase64Url(body), allowMalformed: true).toLowerCase(), isNot(contains('almuerzo')));
      expect(body, isNot(contains('almuerzo')));
    }

    // 6. A second phone, empty, unlocks with the recovery key.
    await first.session!.close();
    final second = _Phone(token, Directory('${root.path}/second')..createSync());
    final gate2 = await second.gate(profile: profile);
    gate2.start();
    await _until(gate2, (s) => s is Unlock || s is Ready);
    expect(gate2.state, isA<Unlock<VaultSession>>());
    expect(await gate2.unlock(recoveryKey), isNull);
    await _until(gate2, (s) => s is Ready || s is Unlock);
    expect(gate2.state, isA<Ready<VaultSession>>());

    // 7. It sees the movement.
    final seen = await second.screens().get<Map<Object?, Object?>>('/v1/transactions');
    final items = (seen.data!['items']! as List).cast<Map<Object?, Object?>>();
    final found = items.where((t) => t['name'] == _name).toList();
    expect(found, hasLength(1));
    expect(found.single['amount'], _amount);
    await second.session!.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
