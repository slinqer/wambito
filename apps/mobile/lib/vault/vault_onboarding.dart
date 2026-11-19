// The welcome of an encrypted (`preview`) account is the vault's to say, as the web's
// `LocalOnboardingRoute` (apps/web/app/features/vault/VaultGate.tsx): the welcome's
// `PATCH /v1/me` is answered by the local backend, which stamps `onboardingCompletedAt` in the
// vault's sealed settings record only, so the server's copy stays empty and its `GET /v1/me` always
// says the welcome is to do. A `plain` account keeps the server's flag.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/session.dart';
import '../local/vault_session.dart';
import 'vault_gate.dart';
import 'vault_providers.dart';

/// Whether the open vault says the welcome is still to do (a signed-up account whose settings have
/// no `onboardingCompletedAt`; never a guest), once that answer is in the session
/// ([SessionController.onboardingFromVault]); null while no vault is open or it is being read. The
/// router waits on the loading route while it is null over an open vault, so a finished account
/// never flashes the welcome. A vault that cannot answer leaves the session's flag as it was.
final vaultOnboardingProvider = NotifierProvider<VaultOnboarding, bool?>(VaultOnboarding.new);

class VaultOnboarding extends Notifier<bool?> {
  @override
  bool? build() {
    // The gate's own session, as the router's `vaultRouteOf` reads the gate.
    final vault = _openVault(ref.watch(vaultGateStateProvider));
    if (vault != null) unawaited(_read(vault));
    return null;
  }

  static VaultSession? _openVault(VaultGateState<VaultSession>? gate) =>
      gate is Ready<VaultSession> ? gate.session : null;

  Future<void> _read(VaultSession vault) async {
    // After [build] has returned: a state set before would be overwritten by its null.
    await Future<void>.value();
    bool? pending;
    try {
      final me = await vault.backend.handle('GET', '/v1/me', const {}, null);
      final body = me?.body;
      if (me != null && me.status == 200 && body is Map) {
        pending = body['isAnonymous'] != true && body['onboardingCompletedAt'] == null;
      }
    } on Object {
      // The session's flag stands.
    }
    if (!_current(vault)) return;
    // The session first: the router reads its flag the moment this answer is known.
    if (pending != null) {
      await ref.read(sessionProvider.notifier).onboardingFromVault(pending: pending);
    }
    if (!_current(vault)) return;
    state = pending ?? ref.read(sessionProvider).onboardingPending;
  }

  bool _current(VaultSession vault) =>
      ref.mounted && _openVault(ref.read(vaultGateStateProvider)) == vault;
}
