import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_cache.dart' show sessionOwnerOf;
import 'package:wambito/local/vault_session.dart' show VaultProfile, VaultSession;
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_gate.dart';
import 'package:wambito/vault/vault_providers.dart';

/// The signed-in account as `GET /v1/me` would say it for a `preview` account (answered at once).
Override previewAccount({String id = 'user-1'}) => vaultAccountProvider.overrideWith((ref) {
  final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
  if (token == null) return SynchronousFuture<VaultAccount?>(null);
  return SynchronousFuture<VaultAccount?>(
    VaultAccount(
      owner: sessionOwnerOf(token),
      profile: VaultProfile(
        id: id,
        email: 'ana@wambito.test',
        isAnonymous: false,
        locale: 'es',
        timezone: 'America/Bogota',
      ),
      mode: EncryptionMode.preview,
    ),
  );
});

class _OpenVault implements VaultSession {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A `preview` account whose vault is open as far as the router is concerned, so its screens show;
/// the screens run on the test's own fakes, not on a real vault.
List<Override> previewOpen() => [
  previewAccount(),
  vaultGateStateProvider.overrideWithValue(Ready<VaultSession>(_OpenVault())),
  vaultSessionProvider.overrideWithValue(null),
];
