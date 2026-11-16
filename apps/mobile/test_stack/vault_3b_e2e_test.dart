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
import 'package:wambito/local/sync.dart' show SyncProblemCode;
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
/// Plain `flutter test` with sqflite_common_ffi; no emulator.
const _merchant = 'panaderia e2e';
const _cents = 1250000;

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

    // 1. Phone A signs in and sets up; keep the recovery key.
    final a = Phone(token, Directory('${root.path}/a')..createSync());
    final gateA = await a.gate(profile: profile);
    gateA.start();
    await until(gateA, (s) => s is Setup<VaultSession> || s is Ready<VaultSession>);
    final recoveryKey = (gateA.state as Setup<VaultSession>).recoveryKey;
    await gateA.confirmSetup();
    await until(gateA, (s) => s is Ready<VaultSession>);
    expect((await a.session!.sync()).problem, isNull);
    await a.session!.close();

    // 2. Phone B pairs through /v2/pairing: its code typed on A, the numbers compared, A approves.
    final b = Phone(token, Directory('${root.path}/b')..createSync());
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
    var removedByAccount = false;
    sessionB.onRemoved(() => removedByAccount = true);

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

    // 4. A removes B with its recovery key (A's app closed: the rotation writes through a store of
    // its own); B's next sync ends deviceRemoved and its vault and keys are gone.
    final storeA = await SqliteStore.open(
      userId,
      directory: a.dir.path,
      factory: databaseFactoryFfi,
      background: true,
    );
    try {
      final rotation = await rotateKeys(
        a.options,
        store: storeA,
        remove: [bWrap!],
        recovery: TypedRecovery(recoveryKey),
      );
      final rotated = await rotation.commit();
      expect(rotated.dropped.map((d) => d.id), contains(bWrap));
    } finally {
      await storeA.close();
    }
    // A's next sync re-seals the vault under the new key version; B meets it and finds itself gone.
    expect((await background()).outcome, BackgroundOutcome.changed);
    expect((await sessionB.sync()).problem, SyncProblemCode.deviceRemoved);
    for (var i = 0; i < 50 && !removedByAccount; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(removedByAccount, isTrue);
    expect(await b.options.storage.deviceWrapId(userId), isNull);

    // 5. A makes a new recovery key: it signs in, the old one does not (the first has the
    // verifier of the rotation's typed key, so the old key worked until now).
    expect((await _recoverySignIn(recoveryKey)).status, 200);
    final fresh = await newRecoveryKey(a.options);
    await fresh.commit();
    expect((await _recoverySignIn(fresh.recoveryKey)).status, 200);
    final old = await _recoverySignIn(recoveryKey);
    expect(old.status, 401);
    expect(old.code, 'recovery_key_invalid');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
