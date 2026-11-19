@Tags(['stack'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/background/background_run.dart';
import 'package:wambito/background/queued_capture.dart';
import 'package:wambito/crypto/crypto.dart' show parseRecoveryKey, recoveryVerifier, toBase64Url;
import 'package:wambito/local/keys.dart' as keys;
import 'package:wambito/local/pairing.dart';
import 'package:wambito/local/rotate.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/vault_lock.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_gate.dart';

import 'support.dart';

/// Stage 3b of the phone against the real dev stack, on the seeded preview account
/// (apps/mobile/scripts/run-vault-e2e.sh resets it first): two phones (each its own folder, so its
/// own vault lease file, and its own in-memory key storage) pair through `/v2/pairing`, a
/// background run on the first saves a queued capture that the second then reads, the first removes
/// the second with its recovery key (the second's next sync ends `deviceRemoved`) and a new recovery
/// key signs in while the old one no longer does.
///
/// A vault session is one per process and account, so only one phone has its session open at a
/// time; pairing, the removal and the background run need no session of the other.
///
/// The restore tests run after it, in order, on the same account and phone A (one sign-in for the
/// file): a new phone C pairs with A, then a delete on A is restored on C, and an old client's
/// delete (no body on the tombstone) is `not_found` on C. The last test signs a phone D in again
/// with its vault kept, and checks that a removal still cuts off its new session.
///
/// Plain `flutter test` with sqflite_common_ffi; no emulator.
const _merchant = 'panaderia e2e';
const _cents = 1250000;

/// Set by the first test, used by the restore tests after it.
late String _token;
late VaultProfile _profile;
late Phone _a;

Future<VaultSession> _open(Phone phone, VaultProfile profile) async {
  final gate = await phone.gate(profile: profile);
  gate.start();
  await until(gate, (s) => s is Ready<VaultSession>);
  return phone.session!;
}

/// `POST /v2/recovery/sign-in` for a typed recovery key: the status and the problem code.
Future<({int status, Object? code})> _recoverySignIn(String recoveryKey) async {
  final secret = parseRecoveryKey(recoveryKey);
  final verifier = await recoveryVerifier(secret);
  final res = await Dio().postUri<Object?>(
    api.replace(path: '/api/v2/recovery/sign-in'),
    data: {'lookup': toBase64Url(verifier.lookup), 'auth': toBase64Url(verifier.auth)},
    options: Options(validateStatus: (_) => true),
  );
  final body = res.data;
  return (status: res.statusCode!, code: body is Map ? body['code'] : null);
}

void main() {
  sqfliteFfiInit();
  late Directory root;
  setUpAll(() => root = Directory.systemTemp.createTempSync('wambito-vault-3b-e2e'));
  tearDownAll(() => root.deleteSync(recursive: true));

  test('two phones pair, a background run syncs a capture, a device is removed and the recovery key changes', () async {
    final (:token, :profile) = await signIn();
    _token = token;
    _profile = profile;

    // 1. Phone A signs in and sets up; keep the recovery key.
    final a = _a = Phone(token, Directory('${root.path}/a')..createSync());
    final gateA = await a.gate(profile: profile);
    gateA.start();
    await until(gateA, (s) => s is Setup<VaultSession> || s is Ready<VaultSession>);
    final recoveryKey = (gateA.state as Setup<VaultSession>).recoveryKey;
    await gateA.confirmSetup();
    await until(gateA, (s) => s is Ready<VaultSession>);
    expect((await a.session!.sync()).problem, isNull);
    await a.session!.close();

    // 2. Phone B pairs through /v2/pairing: its code typed on A, the numbers compared, A approves.
    // B signs in on its own, as a second phone does: its wrap belongs to its own session, which a
    // removal ends (with A's session shared, the server would keep it for A's wrap).
    final (token: tokenB, profile: _) = await signIn();
    final b = Phone(tokenB, Directory('${root.path}/b')..createSync());
    final pairing = await startPairing(b.options);
    final approver = await findPairing(a.options, code: pairing.code);
    final numberOnB = await pairing.number();
    expect(await approver.number(), numberOnB);
    final finishing = pairing.finish();
    await approver.approve();
    await finishing;
    final bWrap = await b.options.storage.deviceWrapId(userId);
    expect(bWrap, isNotNull);
    // B opens its vault and keeps it open: a vault session is one per process and account.
    final sessionB = await _open(b, profile);

    // 3. A background run on A (its app closed) saves a queued capture, then syncs it.
    final queued = QueuedCapture(
      key: 'e2e-capture-1',
      kind: 'expense',
      amount: _cents,
      currency: 'EUR',
      merchant: _merchant,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      source: 'revolut',
    );
    final acks = <List<String>>[];
    // The headless engine on A's folder, as WorkManager runs it with the app closed.
    Future<BackgroundReport> background({
      List<QueuedCapture> captures = const [],
      Future<void> Function(List<String>, List<String>)? ack,
    }) => runBackground(
      BackgroundDeps(
        token: () async => token,
        recall: (_) async =>
            VaultAccount(profile: profile, mode: EncryptionMode.preview, owner: 'e2e'),
        loadKeys: (id) => keys.loadLocalKeys(id, a.options.storage),
        openStore: (id) => SqliteStore.open(
          id,
          directory: a.dir.path,
          factory: databaseFactoryFfi,
          background: true,
        ),
        network: (_) => a.network,
        lease: (id) => tryLease(id, holder: 'background', directory: a.dir.path),
        now: DateTime.now,
      ),
      BackgroundEffects(widget: (_, _) async {}, due: (_, _) async {}),
      captures: captures,
      ack: ack,
    );

    final report = await background(captures: [queued], ack: (saved, _) async => acks.add(saved));
    expect(report.outcome, BackgroundOutcome.changed);
    expect(report.captured.single['result'], 'created');
    expect(acks.single, [queued.key]);

    // B syncs and reads it.
    expect((await sessionB.sync()).problem, isNull);
    final seen = await b.screens().get<Map<Object?, Object?>>('/v1/transactions');
    final found = (seen.data!['items']! as List)
        .cast<Map<Object?, Object?>>()
        .where((t) => t['name'] == _merchant)
        .toList();
    expect(found, hasLength(1));
    expect(found.single['amount'], -_cents);

    // 4. A removes B as Settings → Security does (`SecurityApi.removeDevice`): `DELETE /v2/keys/{id}`
    // deletes B's wrap and ends B's session, with no rotation. B's next call is refused (401). The
    // seeded account is a `plain` user let into preview (`E2E_PREVIEW_USER_IDS`), so the server
    // says `unauthenticated` rather than `device_removed` (spec 2026-11-15 section 11: the code is
    // for encrypted users); what the phone does with `device_removed` is in test/api.
    await keys.api(a.options)('/v2/keys/${bWrap!}', method: 'DELETE');
    final refused = await b.network.get<Object?>(
      '/v1/me',
      options: Options(validateStatus: (_) => true),
    );
    expect(refused.statusCode, 401);
    final left = (await keys.api(a.options)('/v2/keys')).data! as Map<String, Object?>;
    expect(
      (left['wraps']! as List).cast<Map<String, Object?>>().map((w) => w['id']),
      isNot(contains(bWrap)),
    );
    await sessionB.close();

    // 5. A makes a new recovery key: it signs in, the old one does not (the old key's verifier was
    // set up with the account, so it worked until now).
    expect((await _recoverySignIn(recoveryKey)).status, 200);
    final fresh = await newRecoveryKey(a.options);
    await fresh.commit();
    expect((await _recoverySignIn(fresh.recoveryKey)).status, 200);
    final old = await _recoverySignIn(recoveryKey);
    expect(old.status, 401);
    expect(old.code, 'recovery_key_invalid');
  }, timeout: const Timeout(Duration(minutes: 4)));

  /// Phone C, paired with A by the first restore test.
  late Phone c;

  /// Opens [phone]'s session (closing the other's: one per process), runs [body], closes it.
  Future<T> on<T>(Phone phone, Future<T> Function(VaultSession session) body) async {
    final session = await _open(phone, _profile);
    try {
      return await body(session);
    } finally {
      await session.close();
    }
  }

  Future<List<Map<Object?, Object?>>> movements(Phone phone, String name) async {
    final seen = await phone.screens().get<Map<Object?, Object?>>('/v1/transactions');
    return (seen.data!['items']! as List)
        .cast<Map<Object?, Object?>>()
        .where((t) => t['name'] == name)
        .toList();
  }

  Future<String> create(Phone phone, String name) async {
    final categories = (await phone.screens().get<Object?>('/v1/categories')).data;
    final list = categories is Map ? categories['items'] as List : categories! as List;
    final category = (list.cast<Map<Object?, Object?>>().firstWhere(
      (c) => c['kind'] == 'expense',
    ))['id'];
    final created = await phone.screens().post<Map<Object?, Object?>>(
      '/v1/transactions',
      data: {'name': name, 'amount': -1300, 'categoryId': category, 'date': '2026-10-21'},
    );
    expect(created.statusCode, inInclusiveRange(200, 299));
    return created.data!['id']! as String;
  }

  /// The server's row of [id] (`GET /v2/sync` from the start).
  Future<Map<String, Object?>> serverRow(String id) async {
    final raw = await _a.network.get<Map<String, Object?>>(
      '/v2/sync',
      queryParameters: {'since': 0, 'base': 0, 'limit': 1000},
      options: Options(headers: {'x-wambito-user': userId}),
    );
    return (raw.data!['records']! as List).cast<Map<String, Object?>>().firstWhere(
      (r) => r['id'] == id,
    );
  }

  test('a delete on one phone is restored on the other', () async {
    const name = 'panaderia restore e2e';
    // A creates a movement and syncs; phone C pairs with A and syncs it.
    final id = await on(_a, (session) async {
      final id = await create(_a, name);
      expect((await session.sync()).problem, isNull);
      return id;
    });
    c = Phone(_token, Directory('${root.path}/c')..createSync());
    final pairing = await startPairing(c.options);
    final approver = await findPairing(_a.options, code: pairing.code);
    final numberOnC = await pairing.number();
    expect(await approver.number(), numberOnC);
    final finishing = pairing.finish();
    await approver.approve();
    await finishing;
    await on(c, (session) async {
      expect((await session.sync()).problem, isNull);
      expect(await movements(c, name), hasLength(1));
    });

    // A deletes it and syncs: the tombstone carries its sealed body.
    await on(_a, (session) async {
      final deleted = await _a.screens().delete<Object?>('/v1/transactions/$id');
      expect(deleted.statusCode, 204);
      expect((await session.sync()).problem, isNull);
    });
    final tombstone = await serverRow(id);
    expect(tombstone['deleted'], isTrue);
    expect(tombstone['body'], isA<String>());

    // C syncs (it is gone), restores it through its local backend and syncs.
    await on(c, (session) async {
      expect((await session.sync()).problem, isNull);
      expect(await movements(c, name), isEmpty);
      final restored = await c.screens().post<Map<Object?, Object?>>(
        '/v1/transactions/$id/restore',
      );
      expect(restored.statusCode, 200);
      expect(restored.data!['name'], name);
      expect((await session.sync()).problem, isNull);
    });
    expect((await serverRow(id))['deleted'], isFalse);

    // A syncs and sees it live, as it was.
    await on(_a, (session) async {
      expect((await session.sync()).problem, isNull);
      final found = await movements(_a, name);
      expect(found, hasLength(1));
      expect(found.single['amount'], -1300);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a restore of an old-client delete is not_found', () async {
    const name = 'panaderia old client e2e';
    // A creates a movement and syncs, while C is closed.
    final id = await on(_a, (session) async {
      final id = await create(_a, name);
      expect((await session.sync()).problem, isNull);
      return id;
    });
    // An old client deletes it: a tombstone with no body.
    final row = await serverRow(id);
    final pushed = await _a.network.post<Map<String, Object?>>(
      '/v2/sync',
      data: {
        'changes': [
          {
            'id': id,
            'type': 'transaction',
            'baseVersion': row['version'],
            'deleted': true,
            'keyV': row['keyV'],
            'encV': 1,
            'body': null,
          },
        ],
      },
      options: Options(headers: {'x-wambito-user': userId}),
    );
    final result = (pushed.data!['results']! as List).single as Map;
    expect(result['version'], isA<int>(), reason: '$result');
    final tombstone = await serverRow(id);
    expect([tombstone['deleted'], tombstone['body']], [true, null]);

    // C, which never had it, syncs: nothing to restore from.
    await on(c, (session) async {
      expect((await session.sync()).problem, isNull);
      expect(await movements(c, name), isEmpty);
      // The local backend's problem answers reach the caller as a DioException.
      final restore = await c
          .screens()
          .post<Object?>('/v1/transactions/$id/restore')
          .then<Object?>((r) => r, onError: (Object e) => e);
      expect(restore, isA<DioException>());
      final response = (restore as DioException).response;
      expect(response?.statusCode, 404);
      expect((response!.data! as Map)['code'], 'not_found');
      // Nothing was written: no change to push, the server still has the tombstone.
      expect((await session.sync()).problem, isNull);
      expect(await movements(c, name), isEmpty);
    });
    final after = await serverRow(id);
    expect([after['deleted'], after['body'], after['version']], [true, null, tombstone['version']]);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a phone back on a new session with its vault kept is cut off by a removal', () async {
    // 1. D signs in (session 1), pairs with A and opens its vault: its wrap is PUT under session 1.
    final (token: token1, profile: _) = await signIn();
    final dir = Directory('${root.path}/d')..createSync();
    final d1 = Phone(token1, dir);
    final pairing = await startPairing(d1.options);
    final approver = await findPairing(_a.options, code: pairing.code);
    expect(await approver.number(), await pairing.number());
    final finishing = pairing.finish();
    await approver.approve();
    await finishing;
    final dWrap = await d1.options.storage.deviceWrapId(userId);
    expect(dWrap, isNotNull);
    await on(d1, (session) async => expect((await session.sync()).problem, isNull));

    // 2. D signs in again (session 2), its vault and keys kept (as after a session that expired),
    // and opens: it lists the keys and PUTs its own wrap back, which links it to session 2.
    final (token: token2, profile: _) = await signIn();
    final d2 = Phone(token2, dir, storage: d1.storage);
    final session = await _open(d2, _profile);
    expect(await d2.options.storage.deviceWrapId(userId), dWrap);
    expect((await session.sync()).problem, isNull);

    // 3. A removes D (`DELETE /v2/keys/{id}`): the server ends the session D's wrap is linked to
    // now, so D's next call on session 2 is refused.
    await keys.api(_a.options)('/v2/keys/${dWrap!}', method: 'DELETE');
    final refused = await d2.network.get<Object?>(
      '/v1/me',
      options: Options(validateStatus: (_) => true),
    );
    expect(refused.statusCode, 401);
    await session.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
