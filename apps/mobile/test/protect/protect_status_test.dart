// "Protect your data"'s status (phone-first spec 5.2): only for a `preview` account without email
// whose vault is open; the recovery key from the synced settings, the passkey from the wraps.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/passkeys.dart' show passkeysSupportedProvider;
import 'package:wambito/protect/protect_status.dart';
import 'package:wambito/settings/passkeys_settings.dart' show settingsPasskeysProvider;
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_providers.dart' show vaultSessionProvider;

import '../settings/security/fake_security.dart';
import 'fakes.dart';

Future<ProtectStatus?> statusOf({
  Override? account,
  FakeVault? vault,
  bool open = true,
  bool supported = true,
  bool passkeyWrap = false,
  List<String> passkeys = const [],
}) async {
  final session = vault ?? FakeVault();
  await session.seeded;
  final container = ProviderContainer(
    overrides: [
      account ?? accountOf(),
      vaultSessionProvider.overrideWithValue(open ? session : null),
      passkeysSupportedProvider.overrideWith((ref) async => supported),
      securityApiProvider.overrideWithValue(FakeSecurity(snapshotOf(passkeyWrap: passkeyWrap))),
      settingsPasskeysProvider.overrideWithValue(
        FakeSettingsPasskeys([for (final id in passkeys) passkeyItem(id)]),
      ),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(protectStatusProvider, (_, _) {});
  addTearDown(sub.close);
  return container.read(protectStatusProvider.future);
}

void main() {
  test('null for plain, for an email account and while the vault is closed', () async {
    expect(await statusOf(account: accountOf(mode: EncryptionMode.plain)), isNull);
    expect(await statusOf(account: accountOf(anonymous: false)), isNull);
    expect(await statusOf(open: false), isNull);
    // the account without email, vault open: a status
    expect(await statusOf(), isNotNull);
  });

  test('nothing done: 0 of 2, not protected', () async {
    final status = (await statusOf())!;
    expect(status.recoveryKey, isFalse);
    expect(status.passkey, isFalse);
    expect(status.done, 0);
    expect(status.protected, isFalse);
  });

  test('a saved recovery key counts', () async {
    final status = (await statusOf(
      vault: FakeVault(recoveryKeySavedAt: '2026-11-18T10:00:00.000Z'),
    ))!;
    expect(status.recoveryKey, isTrue);
    expect(status.done, 1);
    expect(status.protected, isTrue);
  });

  test('a passkey wrap counts, and both make 2', () async {
    final status = (await statusOf(
      vault: FakeVault(recoveryKeySavedAt: '2026-11-18T10:00:00.000Z'),
      passkeyWrap: true,
      passkeys: ['cred-1'],
    ))!;
    expect(status.passkey, isTrue);
    expect(status.passkeyWithoutPrf, isFalse);
    expect(status.done, 2);
  });

  test('a passkey without a wrap counts as not done and sets passkeyWithoutPrf', () async {
    final status = (await statusOf(passkeys: ['cred-1']))!;
    expect(status.passkey, isFalse);
    expect(status.passkeyWithoutPrf, isTrue);
    expect(status.done, 0);
    expect(status.protected, isFalse);
  });

  test('passkeyOffered is false when the phone reports no passkey support', () async {
    expect((await statusOf(supported: false))!.passkeyOffered, isFalse);
    expect((await statusOf())!.passkeyOffered, isTrue);
  });

  test('the recovery key is read straight from the settings record', () async {
    final vault = FakeVault(recoveryKeySavedAt: '2026-11-18T10:00:00.000Z');
    await vault.seeded;
    expect(await recoveryKeySavedAt(vault.store), '2026-11-18T10:00:00.000Z');
    expect(await recoveryKeySavedAt(FakeVault().store), isNull);
  });
}
