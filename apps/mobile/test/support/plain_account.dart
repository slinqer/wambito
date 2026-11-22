import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_cache.dart' show sessionOwnerOf;
import 'package:wambito/local/vault_session.dart' show VaultProfile;
import 'package:wambito/vault/encryption_mode.dart';

/// The signed-in account as `GET /v1/me` would say it for a `plain` account: the app's screens run
/// on their own fakes, and the router asks the account's mode before it lets a screen open (a mode
/// nobody could learn shows the vault's Locked view), so a test that is not about the vault says
/// the account is `plain` instead of asking a server that is not there.
///
/// It answers at once (a [SynchronousFuture]): no frame waits for it, so the screens come up in the
/// order they always did.
Override plainAccount({String id = 'user-1'}) => vaultAccountProvider.overrideWith((ref) {
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
      mode: EncryptionMode.plain,
    ),
  );
});
