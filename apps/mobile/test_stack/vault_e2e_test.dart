@Tags(['stack'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/crypto/crypto.dart' show fromBase64Url;
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/vault_gate.dart';

import 'support.dart';

/// The phone's vault against the real dev stack (`docker compose up`: API, Postgres, Mailpit), as
/// apps/web/e2e/vault.spec.ts does for the browser: the seeded preview account
/// (preview@wambito.test, id preview-e2e; apps/mobile/scripts/run-vault-e2e.sh resets it first)
/// signs in with an email code, sets up its keys through [VaultGate], adds a movement, syncs, and a
/// second phone (an empty folder and key storage) unlocks with the recovery key and sees it. The
/// server only ever holds ciphertext: no record body decodes to the movement's name.
///
/// Plain `flutter test` with sqflite_common_ffi and an in-memory key storage; no emulator.
const _name = 'almuerzo e2e';
const _amount = -1250000;

void main() {
  sqfliteFfiInit();
  late Directory root;
  setUpAll(() => root = Directory.systemTemp.createTempSync('wambito-vault-e2e'));
  tearDownAll(() => root.deleteSync(recursive: true));

  test(
    'a preview account sets up, syncs, and a second phone unlocks it with the recovery key',
    () async {
      // 1. Sign in with the email code, as the app's AuthApi does.
      final auth = HttpAuthApi(server: api, hints: hints);
      final old = await mailIds();
      await auth.sendCode(email);
      final token = await auth.verifyCode(email, await readCode(old));
      final me = (await ApiClient.forServer(
        api,
        token: token,
        hints: hints,
      ).api.getDefaultApi().getMe()).data!;
      expect(me.id, userId);
      expect(me.encryption.name, 'preview');
      final profile = VaultProfile(
        id: me.id,
        email: me.email,
        isAnonymous: false,
        locale: 'es',
        timezone: 'America/Bogota',
      );

      // 2. Set up the account through the gate; keep the recovery key.
      final first = Phone(token, Directory('${root.path}/first')..createSync());
      final gate = await first.gate(profile: profile);
      gate.start();
      await until(gate, (s) => s is Setup || s is Ready);
      final setup = gate.state;
      expect(setup, isA<Setup<VaultSession>>());
      final recoveryKey = (setup as Setup<VaultSession>).recoveryKey;
      await gate.confirmSetup();
      await until(gate, (s) => s is Ready || s is Locked);
      expect(gate.state, isA<Ready<VaultSession>>());

      // 3. A movement through the interceptor.
      final screens = first.screens();
      final categories = (await screens.get<Object?>('/v1/categories')).data;
      final list = categories is Map ? categories['items'] as List : categories! as List;
      final category = (list.cast<Map<Object?, Object?>>().firstWhere(
        (c) => c['kind'] == 'expense',
      ))['id'];
      final created = await screens.post<Map<Object?, Object?>>(
        '/v1/transactions',
        data: {'name': _name, 'amount': _amount, 'categoryId': category, 'date': '2026-10-21'},
      );
      expect(created.statusCode, inInclusiveRange(200, 299));

      // 4. Sync.
      final result = await first.session!.sync();
      expect(result.problem, isNull);

      // 5. The server holds ciphertext only.
      final raw = await first.network.get<Map<String, Object?>>(
        '/v2/sync',
        queryParameters: {'since': 0, 'limit': 1000},
      );
      final records = (raw.data!['records']! as List).cast<Map<String, Object?>>();
      expect(records, isNotEmpty);
      for (final r in records) {
        final body = r['body'] as String?;
        if (body == null) continue;
        expect(
          utf8.decode(fromBase64Url(body), allowMalformed: true).toLowerCase(),
          isNot(contains('almuerzo')),
        );
        expect(body, isNot(contains('almuerzo')));
      }

      // 6. A second phone, empty, unlocks with the recovery key.
      await first.session!.close();
      final second = Phone(token, Directory('${root.path}/second')..createSync());
      final gate2 = await second.gate(profile: profile);
      gate2.start();
      await until(gate2, (s) => s is Unlock || s is Ready);
      expect(gate2.state, isA<Unlock<VaultSession>>());
      expect(await gate2.unlock(recoveryKey), isNull);
      await until(gate2, (s) => s is Ready || s is Unlock);
      expect(gate2.state, isA<Ready<VaultSession>>());

      // 7. It sees the movement.
      final seen = await second.screens().get<Map<Object?, Object?>>('/v1/transactions');
      final items = (seen.data!['items']! as List).cast<Map<Object?, Object?>>();
      final found = items.where((t) => t['name'] == _name).toList();
      expect(found, hasLength(1));
      expect(found.single['amount'], _amount);
      await second.session!.close();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
