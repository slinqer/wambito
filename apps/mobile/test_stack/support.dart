/// Shared by the stack tests: the real dev stack's addresses, one phone (folder, in-memory key
/// storage, network, gate over the real keys), the sign-in through Mailpit, a new user without
/// email ([startGuest]) or with one ([signUpWithEmail]), and a browser's half of a web sign-in
/// ([WebSignin], the stand-in for apps/web/app/local/signin.ts).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/device.dart';
import 'package:wambito/home/home_cache.dart' show sessionOwnerOf;
import 'package:wambito/crypto/crypto.dart'
    show
        DeviceKeyPair,
        WrapContext,
        WrapKind,
        fromBase64Url,
        generateDeviceKeyPair,
        openFromPairing,
        pairingCommitment,
        toBase64Url;
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

/// The code of the newest sign-in (or claim) email to [to] that is not in [skip].
Future<String> readCode(Set<String> skip, {String to = email}) async {
  final address = to.toLowerCase();
  final http = Dio();
  for (var i = 0; i < 30; i++) {
    final list = await http.getUri<Map<String, Object?>>(
      mailpit.replace(path: '/api/v1/messages', query: 'limit=200'),
    );
    for (final m in (list.data!['messages']! as List).cast<Map<String, Object?>>()) {
      if (skip.contains(m['ID']) ||
          !(m['To']! as List).cast<Map<String, Object?>>().any(
            (t) => (t['Address']! as String).toLowerCase() == address,
          )) {
        continue;
      }
      final code = RegExp(r'\b(\d{6})\b').firstMatch(m['Subject']! as String)?.group(1);
      if (code != null) return code;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('no sign-in email to $to');
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

/// One phone: its folder, its key storage, the network client and the gate over the real keys, for
/// [account] (default: the seeded preview account). Two phones may share a [storage] (one phone,
/// two accounts: a merge).
class Phone {
  Phone(this.token, this.dir, {String? account, MemoryStorage? storage})
    : account = account ?? userId,
      storage = storage ?? MemoryStorage() {
    network = ApiClient.forServer(
      api,
      token: token,
      hints: hints,
      clientIp: '10.77.${DateTime.now().microsecond % 250}.1',
      development: true,
    ).dio;
    options = KeysOptions(userId: this.account, dio: network, storage: KeyStorage(this.storage));
  }

  final String token;
  final Directory dir;
  final String account;
  final MemoryStorage storage;
  late final Dio network;
  late final KeysOptions options;
  VaultSession? session;

  Future<VaultGate<LocalKeys, VaultSession>> gate({required VaultProfile profile}) async {
    final gate = VaultGate<LocalKeys, VaultSession>(
      VaultGateDeps(
        userId: account,
        loadLocalKeys: () => keys.loadLocalKeys(account, options.storage),
        prepareAccount: () async {
          // As the app's gate: an account without email gets the hidden recovery wrap, no Setup.
          final prepared = await keys.prepareAccount(options, guest: profile.isAnonymous);
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
              // As the app's gate: a kept vault under a new session links its wrap to it.
              sessionOwner: sessionOwnerOf(token),
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
  // An address of its own per request, like [authApi]: a test that signs in twice (two phones)
  // stays under the stack's sign-in limit.
  final auth = authApi();
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

var _addresses = 0;

/// The app's [HttpAuthApi] over the stack, each request from an address of its own
/// (`x-forwarded-for`, which the development stack trusts): Better Auth allows 3 sign-ins per
/// address in 10 seconds, and the phone-first tests make several users at once.
HttpAuthApi authApi() {
  final auth = HttpAuthApi(server: api, hints: hints);
  auth.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        _addresses += 1;
        options.headers['x-forwarded-for'] =
            '10.79.${(_addresses ~/ 250) % 250}.${_addresses % 250 + 1}';
        handler.next(options);
      },
    ),
  );
  return auth;
}

/// A signed-in session of a user made by the test: its token and the profile `GET /v1/me` gave.
typedef SignedUp = ({String token, VaultProfile profile});

/// `GET /v1/me` for [token], as a [VaultProfile]; throws unless the account is `preview` (the stack
/// must run with `NEW_USERS_ENCRYPTED=true`).
Future<VaultProfile> previewProfileOf(String token) async {
  final me = (await ApiClient.forServer(
    api,
    token: token,
    hints: hints,
  ).api.getDefaultApi().getMe()).data!;
  if (me.encryption.name != 'preview') {
    throw StateError('a new user is not preview: start the stack with NEW_USERS_ENCRYPTED=true');
  }
  return VaultProfile(
    id: me.id,
    email: me.email,
    isAnonymous: me.isAnonymous,
    locale: 'es',
    timezone: 'America/Bogota',
  );
}

/// The welcome's "Start" (`POST /auth/sign-in/anonymous`, as the app's AuthApi does): a new user
/// without email.
Future<SignedUp> startGuest() async {
  final token = await authApi().signInAsGuest();
  return (token: token, profile: await previewProfileOf(token));
}

/// A new account for [address], signed in with its emailed code (the API makes the user at the
/// first code).
Future<SignedUp> signUpWithEmail(String address) async {
  final auth = authApi();
  final old = await mailIds();
  await auth.sendCode(address);
  final token = await auth.verifyCode(address, await readCode(old, to: address));
  return (token: token, profile: await previewProfileOf(token));
}

/// What the browser picks up once the phone sealed: the sealed data key, its version and the
/// account, and the data key it opens to.
typedef WebPickup = ({String sealed, int keyV, String userId, Uint8List dataKey});

/// The browser's half of a web sign-in (phone-first spec 8.1, apps/web/app/local/signin.ts), signed
/// out: it holds `N`, opens `POST /v2/signin` with `SHA-256("wambito/v1/pairing-commit" || N.pub)`,
/// shows [qr], reveals `N.pub` once the phone's approver key is there, picks the seal up and opens
/// it with `openFromPairing` under `WrapContext(device, userId, keyV)` (ruling 15).
class WebSignin {
  WebSignin._(this._pair, this.id, this._pollSecret);

  static final _dio = Dio(
    BaseOptions(
      baseUrl: api.replace(path: '/api').toString(),
      validateStatus: (_) => true,
    ),
  );

  final DeviceKeyPair _pair;
  final String id;
  final String _pollSecret;

  /// The QR the browser shows: `wambito://signin?id=<id>&key=<base64url N.pub>`.
  String get qr => 'wambito://signin?id=$id&key=${toBase64Url(_pair.publicKey)}';

  static Future<WebSignin> open({String label = 'e2e browser'}) async {
    final pair = await generateDeviceKeyPair();
    final res = await _dio.post<Map<String, Object?>>(
      '/v2/signin',
      data: {
        'commitment': toBase64Url(await pairingCommitment(pair.publicKey)),
        'remember': false,
        'label': label,
      },
    );
    if (res.statusCode != 201) throw StateError('POST /v2/signin: ${res.statusCode} ${res.data}');
    return WebSignin._(pair, res.data!['id']! as String, res.data!['pollSecret']! as String);
  }

  Options get _poll => Options(headers: {'x-wambito-poll': _pollSecret});

  Future<Map<String, Object?>> _state() async {
    final res = await _dio.get<Map<String, Object?>>('/v2/signin/$id', options: _poll);
    if (res.statusCode != 200) throw StateError('GET /v2/signin/{id}: ${res.statusCode}');
    return res.data!;
  }

  /// Polls until the phone approved, reveals `N.pub`, polls until it sealed, picks up and opens.
  Future<WebPickup> finish() async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    Future<Map<String, Object?>> until(bool Function(Map<String, Object?>) done) async {
      while (DateTime.now().isBefore(deadline)) {
        final state = await _state();
        if (done(state)) return state;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      throw StateError('the web sign-in did not move on');
    }

    final approved = await until((s) => s['approverKey'] != null);
    final approverKey = fromBase64Url(approved['approverKey']! as String);
    final reveal = await _dio.post<Object?>(
      '/v2/signin/$id/reveal',
      data: {'publicKey': toBase64Url(_pair.publicKey)},
      options: _poll,
    );
    if (reveal.statusCode != 204) throw StateError('reveal: ${reveal.statusCode} ${reveal.data}');
    await until((s) => s['ready'] == true);
    final res = await _dio.post<Map<String, Object?>>('/v2/signin/$id/pickup', options: _poll);
    if (res.statusCode != 200) throw StateError('pickup: ${res.statusCode} ${res.data}');
    final sealed = res.data!['sealed']! as String;
    final keyV = res.data!['keyV']! as int;
    final userId = res.data!['userId']! as String;
    final dataKey = await openFromPairing(
      _pair.privateKey,
      WrapContext(kind: WrapKind.device, userId: userId, keyV: keyV),
      fromBase64Url(sealed),
      approverKey,
    );
    return (sealed: sealed, keyV: keyV, userId: userId, dataKey: dataKey);
  }
}
