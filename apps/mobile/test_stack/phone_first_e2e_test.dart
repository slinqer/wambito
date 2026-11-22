@Tags(['stack'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture_auto/capture_platform.dart' show autoCapturePlatformProvider;
import 'package:wambito/crypto/crypto.dart' show recoveryVerifier, toBase64Url;
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/local/db.dart' show listVaultHolds, vaultFileName, vaultHoldOf;
import 'package:wambito/local/ids.dart' show uuidv5;
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/keys.dart' as keys;
import 'package:wambito/local/merge.dart' show foldedName, mergedId;
import 'package:wambito/local/rotate.dart' show newRecoveryKey;
import 'package:wambito/local/signin_approval.dart' show findSigninRequest;
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/stale_vaults.dart' show deleteStaleVaults;
import 'package:wambito/local/vault_lock.dart' show tryLease;
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/merge/merge_controller.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_gate.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../test/capture_auto/fakes.dart' show FakeAutoCapturePlatform;
import '../test/entry/fakes.dart' show FakePasskeys;
import '../test/home/fakes.dart' show FakeCacheStore, FakeWidgetStore;
import 'support.dart';

/// Phone-first accounts (spec docs/superpowers/specs/2026-11-15-phone-first-accounts-design.md)
/// against the real dev stack, started with `NEW_USERS_ENCRYPTED=true` (every new user is
/// `preview`; apps/mobile/scripts/run-vault-e2e.sh checks it first): the first run without email,
/// protected and then given an email; the merge of a guest into an existing account, through
/// [MergeController]; a recovery-key sign-in on a new phone; and a web sign-in approved by the
/// phone. Each run makes its own users, under invented addresses `phone-first-<run>@wambito.test`.
///
/// The email codes are limited per address (5 in 10 minutes), so tests 3 and 4 reuse test 1's
/// phone A (its guest, its recovery key, its `cafeteria`) instead of a new sign-up: run the whole
/// file, in order.
///
/// Plain `flutter test` with sqflite_common_ffi and in-memory key storages; no emulator.
const _cafeteria = 'cafeteria e2e';
const _mercado = 'mercado e2e';

/// The run's own addresses: never the seeded preview account's.
final _run = DateTime.now().millisecondsSinceEpoch;
final _emailA = 'phone-first-$_run@wambito.test';
final _emailB = 'phone-first-$_run-b@wambito.test';

/// Phone A, kept by the first test for the third and fourth.
typedef _PhoneA = ({Phone phone, VaultProfile profile, String recoveryKey});
_PhoneA? _shared;

_PhoneA _phoneA() =>
    _shared ??
    fail(
      'run the whole file: this test needs phone A from "first run without email, protect, then '
      'add an email"',
    );

/// What the script checks in Postgres afterwards (`WAMBITO_E2E_REPORT`, one `key=value` per line):
/// each account this run made (`account=`) and the merged guest (`mergedGuest=`), whose user row
/// must be gone.
void _note(String key, String value) {
  final path = Platform.environment['WAMBITO_E2E_REPORT'];
  if (path != null && path.isNotEmpty) {
    File(path).writeAsStringSync('$key=$value\n', mode: FileMode.append);
  }
}

Future<VaultSession> _open(Phone phone, VaultProfile profile) async {
  final gate = await phone.gate(profile: profile);
  gate.start();
  await until(gate, (s) => s is Ready<VaultSession> || s is Setup<VaultSession>);
  if (gate.state is Setup<VaultSession>) await gate.confirmSetup();
  await until(gate, (s) => s is Ready<VaultSession>);
  return phone.session!;
}

/// `GET <path>` through the vault's interceptor, as the screens call it: the list it answers.
Future<List<Map<Object?, Object?>>> _list(Phone phone, String path) async {
  final data = (await phone.screens().get<Object?>(path)).data;
  final list = data is Map ? data['items']! as List : data! as List;
  return list.cast<Map<Object?, Object?>>();
}

Future<Map<Object?, Object?>> _post(Phone phone, String path, Map<String, Object?> body) async {
  final res = await phone.screens().post<Map<Object?, Object?>>(path, data: body);
  expect(res.statusCode, inInclusiveRange(200, 299), reason: '$path: ${res.data}');
  return res.data!;
}

/// A new expense category named [name], with a seeded one's icon and colour.
Future<String> _category(Phone phone, String name) async {
  final seeded = (await _list(phone, '/v1/categories')).firstWhere((c) => c['kind'] == 'expense');
  final created = await _post(phone, '/v1/categories', {
    'name': name,
    'kind': 'expense',
    'icon': seeded['icon'],
    'color': seeded['color'],
  });
  return created['id']! as String;
}

String _today() => DateTime.now().toIso8601String().substring(0, 10);

/// The records the server holds for the session of [network] (`GET /v2/sync` from 0).
Future<List<Map<String, Object?>>> _serverRecords(Dio network) async {
  final raw = await network.get<Map<String, Object?>>(
    '/v2/sync',
    queryParameters: {'since': 0, 'limit': 1000},
  );
  return (raw.data!['records']! as List).cast<Map<String, Object?>>();
}

/// `GET /v1/me` with [token]: its status.
Future<int> _meStatus(String token) async {
  final res = await Dio().getUri<Object?>(
    api.replace(path: '/api/v1/me'),
    options: Options(headers: {'authorization': 'Bearer $token'}, validateStatus: (_) => true),
  );
  return res.statusCode!;
}

/// `POST /v2/recovery/sign-in` for [typed], parsed as the app parses it: the status and the body.
Future<({int status, Object? body})> _recoverySignIn(String typed) async {
  final verifier = await recoveryVerifier(keys.keysParseRecoveryKey(typed));
  final res = await Dio().postUri<Object?>(
    api.replace(path: '/api/v2/recovery/sign-in'),
    data: {'lookup': toBase64Url(verifier.lookup), 'auth': toBase64Url(verifier.auth)},
    options: Options(validateStatus: (_) => true),
  );
  return (status: res.statusCode!, body: res.data);
}

/// The recovery key typed the way people type it: lower case, dashes every four characters.
String _typedLoosely(String recoveryKey) {
  final bare = recoveryKey.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
  return [
    for (var i = 0; i < bare.length; i += 4)
      bare.substring(i, i + 4 > bare.length ? bare.length : i + 4),
  ].join('-');
}

/// The open vault the merge's target reads ([vaultSessionProvider] in the app, set by the gate).
class _OpenVault extends Notifier<VaultSession?> {
  @override
  VaultSession? build() => null;

  void set(VaultSession? session) => state = session;
}

final _openVault = NotifierProvider<_OpenVault, VaultSession?>(_OpenVault.new);

/// The app as far as a merge goes, on phone D: the real session controller and auth over the
/// stack, `GET /v1/me` of the stack for the signed-in account, the phone's key storage and its vault
/// folder; the open vault is the one the test's gate opened ([_openVault]).
ProviderContainer _phoneApp(Directory dir, MemoryStorage storage) {
  Future<void> forget(String id, KeyStorage keyStorage) async {
    await databaseFactoryFfi.deleteDatabase(p.join(dir.path, vaultFileName(id)));
    await keyStorage.deleteAll(id);
  }

  final container = ProviderContainer(
    overrides: [
      authApiProvider.overrideWithValue(authApi()),
      passkeysProvider.overrideWithValue(FakePasskeys(isSupported: false)),
      widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
      homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
      autoCapturePlatformProvider.overrideWithValue(FakeAutoCapturePlatform()),
      keyStorageProvider.overrideWithValue(KeyStorage(storage)),
      forgetVaultProvider.overrideWithValue(forget),
      vaultAccountProvider.overrideWith((ref) async {
        final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
        if (token == null) return null;
        final profile = await previewProfileOf(token);
        final owner = sessionOwnerOf(token);
        ref.read(knownAccountProvider)
          ..owner = owner
          ..id = profile.id;
        return VaultAccount(owner: owner, profile: profile, mode: EncryptionMode.preview);
      }),
      vaultSessionProvider.overrideWith((ref) => ref.watch(_openVault)),
      mergeDepsProvider.overrideWithValue(
        MergeDeps(
          listHolds: () => listVaultHolds(directory: dir.path, factory: databaseFactoryFfi),
          openSource: (id) => SqliteStore.open(
            id,
            directory: dir.path,
            factory: databaseFactoryFfi,
            background: true,
          ),
          lease: (id) => tryLease(id, holder: 'app', directory: dir.path),
          storage: const FlutterSecureStorage(),
          now: DateTime.now,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _accountOf(ProviderContainer container, String id) async {
  for (var i = 0; i < 100; i++) {
    final account = container.read(currentVaultAccountProvider);
    if (account?.profile.id == id) return;
    try {
      await container.read(vaultAccountProvider.future);
    } on Object {
      // Asked again below.
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('the app never signed in to $id');
}

void main() {
  // The session controller and the merge read the app's secure storage (the plugin's mock here)
  // and its bindings; the binding's fake HTTP client is put back to the real one: the stack is real.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  late Directory root;
  setUpAll(() => root = Directory.systemTemp.createTempSync('wambito-phone-first-e2e'));
  tearDownAll(() => root.deleteSync(recursive: true));

  test('first run without email, protect, then add an email', () async {
    // 1. "Start": a new user without email, encrypted.
    final (:token, :profile) = await startGuest();
    expect(profile.isAnonymous, isTrue);
    _note('account', profile.id);

    // 2. Its vault through the gate: the hidden recovery wrap, no recovery key shown.
    final a = Phone(token, Directory('${root.path}/a')..createSync(), account: profile.id);
    final gate = await a.gate(profile: profile);
    gate.start();
    await until(
      gate,
      (s) => s is Ready<VaultSession> || s is Setup<VaultSession> || s is Locked<VaultSession>,
    );
    expect(gate.state, isA<Ready<VaultSession>>());
    final keyV = (await keys.loadLocalKeys(profile.id, a.options.storage))!.keyring.current;

    // 3. A movement, synced.
    final category = (await _list(
      a,
      '/v1/categories',
    )).firstWhere((c) => c['kind'] == 'expense')['id'];
    await _post(a, '/v1/transactions', {
      'name': _cafeteria,
      'amount': -450000,
      'categoryId': category,
      'date': _today(),
    });
    expect((await a.session!.sync()).problem, isNull);

    // 4. "Protect your data": a recovery key the person saw, saved with its verifier.
    final prepared = await newRecoveryKey(a.options);
    await prepared.commit();
    final wraps = await keys.listWraps(keys.api(a.options));
    final recovery = wraps.where((w) => w.kind == 'recovery').toList();
    expect(recovery, hasLength(1));
    expect(recovery.single.keyV, keyV);
    final verified = await _recoverySignIn(prepared.recoveryKey);
    expect(verified.status, 200, reason: '${verified.body}');
    expect((verified.body! as Map)['userId'], profile.id);

    // 5. Add an email: the claim's code from Mailpit; the same user, now with the email.
    final auth = authApi();
    final old = await mailIds();
    await auth.claimSend(token, _emailA);
    await auth.claimVerify(token, _emailA, await readCode(old, to: _emailA));
    final claimed = await previewProfileOf(token);
    expect(claimed.id, profile.id);
    expect(claimed.email, _emailA);
    expect(claimed.isAnonymous, isFalse);

    await a.session!.close();
    _shared = (phone: a, profile: claimed, recoveryKey: prepared.recoveryKey);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('merge into an existing account', () async {
    // 1. Phone B: an account with an email, set up with its recovery key, with a movement in a
    // category of its own.
    final b = await signUpWithEmail(_emailB);
    expect(b.profile.isAnonymous, isFalse);
    _note('account', b.profile.id);
    final phoneB = Phone(b.token, Directory('${root.path}/b')..createSync(), account: b.profile.id);
    final gateB = await phoneB.gate(profile: b.profile);
    gateB.start();
    await until(gateB, (s) => s is Setup<VaultSession> || s is Ready<VaultSession>);
    final recoveryKeyB = (gateB.state as Setup<VaultSession>).recoveryKey;
    await gateB.confirmSetup();
    await until(gateB, (s) => s is Ready<VaultSession>);
    final treats = await _category(phoneB, 'Antojos e2e');
    await _post(phoneB, '/v1/transactions', {
      'name': _mercado,
      'amount': -780000,
      'categoryId': treats,
      'date': _today(),
    });
    expect((await phoneB.session!.sync()).problem, isNull);
    await phoneB.session!.close();

    // 2. Phone D, a guest of its own (test 1's phone A stays as it is): `cafeteria` in a category
    // whose folded name is B's, and a monthly rule with this month's occurrence deleted (the carry
    // pushes it as a new tombstone). Synced: the server holds the guest's own ids.
    final dDir = Directory('${root.path}/d')..createSync();
    final dStorage = MemoryStorage();
    final d = await startGuest();
    final guestId = d.profile.id;
    final guest = Phone(d.token, dDir, account: guestId, storage: dStorage);
    await _open(guest, d.profile);
    final sameName = await _category(guest, '  ANTOJOS E2E ');
    await _post(guest, '/v1/transactions', {
      'name': _cafeteria,
      'amount': -320000,
      'categoryId': sameName,
      'date': _today(),
    });
    final month = _today().substring(0, 7);
    final rule = await _post(guest, '/v1/recurrences', {
      'name': 'arriendo e2e',
      'amount': -90000000,
      'categoryId': sameName,
      'frequency': 'monthly',
      'dayOfMonth': 1,
      'startDate': '$month-01',
    });
    final ruleId = rule['id']! as String;
    final occurrence = (await _list(
      guest,
      '/v1/transactions?month=$month',
    )).firstWhere((t) => t['recurrenceId'] == ruleId);
    final removed = await guest.screens().delete<Object?>('/v1/transactions/${occurrence['id']}');
    expect(removed.statusCode, 204);
    expect((await guest.session!.sync()).problem, isNull);
    final guestOwned = {for (final r in await _serverRecords(guest.network)) r['id']! as String};
    expect(guestOwned, contains(occurrence['id']));
    await guest.session!.close();

    // 3. The app on phone D, in the guest's session: adding B's email is refused, it is taken.
    // ignore: invalid_use_of_visible_for_testing_member, the plugin's mock (test_stack is a test)
    FlutterSecureStorage.setMockInitialValues({
      SessionStore.tokenKey: d.token,
      SessionStore.guestKey: 'true',
    });
    final app = _phoneApp(dDir, dStorage);
    final session = app.read(sessionProvider.notifier);
    await session.ready;
    await _accountOf(app, guestId);
    await expectLater(
      session.claimEmail(_emailB),
      throwsA(isA<AuthFailure>().having((f) => (f.status, f.code), 'answer', (409, 'email_taken'))),
    );

    // 4. "Bring this phone's data into it?": yes. The merge holds the guest's vault and keeps its
    // token, then D signs in to B with the code.
    final merge = app.read(mergeControllerProvider.notifier);
    await merge.begin(_emailB);
    expect(app.read(mergeControllerProvider), isA<MergeSigningIn>());
    final old = await mailIds();
    await session.sendCode(_emailB, replaceGuest: true);
    await session.verifyCode(_emailB, await readCode(old, to: _emailB), replaceGuest: true);
    final tokenOnD = app.read(sessionProvider).stored!.token;
    expect(tokenOnD, isNot(d.token));
    await _accountOf(app, b.profile.id);
    await merge.resume();
    expect(app.read(mergeControllerProvider), isA<MergeWaitingUnlock>());

    // The sweep that B's `GET /v1/me` runs keeps the held guest vault and its keys.
    await deleteStaleVaults(
      b.profile.id,
      forget: (id) => app.read(forgetVaultProvider)(id, KeyStorage(dStorage)),
      storage: dStorage,
      directory: () async => dDir.path,
      holdOf: (id) => vaultHoldOf(id, directory: dDir.path, factory: databaseFactoryFfi),
    );
    expect(File(p.join(dDir.path, vaultFileName(guestId))).existsSync(), isTrue);
    expect(dStorage.values.keys.where((k) => k.startsWith('wambito.vault.$guestId.')), isNotEmpty);

    // 5. D unlocks B with B's recovery key; every change it pushes is recorded.
    final onD = Phone(tokenOnD, dDir, account: b.profile.id, storage: dStorage);
    final pushed = <Map<String, Object?>>[];
    onD.network.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST' && options.path == '/v2/sync') {
            final data = options.data;
            if (data is Map && data['changes'] is List) {
              pushed.addAll((data['changes'] as List).cast<Map<String, Object?>>());
            }
          }
          handler.next(options);
        },
      ),
    );
    final gateD = await onD.gate(profile: b.profile);
    gateD.start();
    await until(gateD, (s) => s is Unlock<VaultSession> || s is Ready<VaultSession>);
    expect(gateD.state, isA<Unlock<VaultSession>>());
    expect(await gateD.unlock(recoveryKeyB), isNull);
    await until(gateD, (s) => s is Ready<VaultSession>);
    app.read(_openVault.notifier).set(onD.session);
    expect(app.read(mergeTargetProvider), isNotNull);

    // 6. The carry, the upload until the outbox is empty, the guest deleted.
    await merge.run();
    expect(app.read(mergeControllerProvider), isA<MergeDone>());
    _note('mergedGuest', guestId);
    expect(await _meStatus(d.token), 401);
    expect(File(p.join(dDir.path, vaultFileName(guestId))).existsSync(), isFalse);

    // P17: no id the guest owns on the server was pushed again; the deleted occurrence went as a
    // new tombstone (no base version, a sealed body) and the server took it.
    expect(pushed, isNotEmpty);
    expect(pushed.map((c) => c['id']).where(guestOwned.contains), isEmpty);
    final tombstoneId = uuidv5(mergedId(b.profile.id, ruleId), '$month:0');
    final tombstone = pushed.lastWhere((c) => c['id'] == tombstoneId);
    expect(tombstone['deleted'], isTrue);
    expect(tombstone['baseVersion'], isNull);
    expect(tombstone['body'], isA<String>());
    final onServer = (await _serverRecords(onD.network)).firstWhere((r) => r['id'] == tombstoneId);
    expect(onServer['deleted'], isTrue);
    expect(onServer['version'], greaterThan(0));
    await onD.session!.close();
    app.read(_openVault.notifier).set(null);

    // 7. Phone B syncs: both movements, the folded category once, `cafeteria` in B's category.
    await _open(phoneB, b.profile);
    final movements = await _list(phoneB, '/v1/transactions');
    final cafeteria = movements.where((t) => t['name'] == _cafeteria).toList();
    expect(cafeteria, hasLength(1));
    expect(movements.where((t) => t['name'] == _mercado), hasLength(1));
    expect(cafeteria.single['categoryId'], treats);
    final categories = await _list(phoneB, '/v1/categories?includeArchived=true');
    expect(
      categories.where((c) => foldedName(c['name']! as String) == 'antojos e2e'),
      hasLength(1),
    );
    await phoneB.session!.close();
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('recovery key sign-in on a new phone', () async {
    // Needs test 1's phone A (one email code fewer per run): its account and recovery key.
    final a = _phoneA();
    final typed = _typedLoosely(a.recoveryKey);
    expect(typed, isNot(a.recoveryKey));

    // Signed out, phone C signs in with the key as typed (parsed as Unlock parses it).
    final verifier = await recoveryVerifier(keys.keysParseRecoveryKey(typed));
    final signedIn = await authApi().recoverySignIn(verifier.lookup, verifier.auth);
    expect(signedIn.userId, a.profile.id);
    final profile = await previewProfileOf(signedIn.token);
    expect(profile.id, a.profile.id);

    // It unlocks with the same text and sees A's movement.
    final c = Phone(
      signedIn.token,
      Directory('${root.path}/c')..createSync(),
      account: a.profile.id,
    );
    final gate = await c.gate(profile: profile);
    gate.start();
    await until(gate, (s) => s is Unlock<VaultSession> || s is Ready<VaultSession>);
    expect(gate.state, isA<Unlock<VaultSession>>());
    expect(await gate.unlock(typed), isNull);
    await until(gate, (s) => s is Ready<VaultSession>);
    final movements = await _list(c, '/v1/transactions');
    expect(movements.where((t) => t['name'] == _cafeteria), hasLength(1));
    await c.session!.close();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('approving a web QR', () async {
    // Needs test 1's phone A (one email code fewer per run): it approves.
    final a = _phoneA();
    final web = await WebSignin.open();
    final picking = web.finish();

    // A scans the QR, approves and seals (a scanned QR compares no number).
    final approval = await findSigninRequest(a.phone.options, qr: web.qr);
    expect(approval.label, 'e2e browser');
    expect(approval.comparesNumber, isFalse);
    expect(await approval.approve(), isNull);
    await approval.seal();

    // The browser opened A's data key, for A.
    final picked = await picking;
    expect(picked.userId, a.profile.id);
    final same = await keys.withDataKey(
      a.phone.options,
      (dataKey, keyV) async =>
          keyV == picked.keyV && toBase64Url(dataKey) == toBase64Url(picked.dataKey),
    );
    expect(same, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
