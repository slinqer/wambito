// The merge of this phone's anonymous account into an existing email account (phone-first spec
// 7.2): the phone's vault is held (`merging`, target = the email) and its session token kept
// aside before any code is sent; the person signs in to the email account and unlocks it; then
// the currency check, the carry into the account's vault (lib/local/merge.dart), the upload until
// the outbox is empty, and only then `DELETE /v1/me` of the anonymous user and the old vault
// forgotten. Every step resumes after a crash: the hold keeps the old vault through the sweep, and
// `meta.mergeCarried` in it says the carry committed, so it never runs twice over later edits.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/auth_api.dart';
import '../api/session.dart';
import '../local/db.dart' show VaultHold, VaultHoldKind, listVaultHolds;
import '../local/merge.dart';
import '../local/sqlite_store.dart';
import '../crypto/records.dart' show RecordType;
import '../local/store.dart' show FinanceStore, ReadOptions;
import '../local/vault_lock.dart';
import '../local/vault_session.dart' show appLeaseWait;
import '../storage/secure_storage.dart';
import '../vault/encryption_mode.dart';
import '../vault/vault_providers.dart';

/// Where a merge stands.
sealed class MergeState {
  const MergeState();
}

/// No merge on this phone.
class MergeIdle extends MergeState {
  const MergeIdle();
}

/// The phone's vault is held and its token kept; the person is signing in to [email].
class MergeSigningIn extends MergeState {
  const MergeSigningIn(this.email);

  final String email;
}

/// Signed in to the email account: its vault must be unlocked (and downloaded) before the carry.
class MergeWaitingUnlock extends MergeState {
  const MergeWaitingUnlock();
}

/// The phone's records are in [phone]'s currency and the account's in [account]'s: nothing was
/// written; the person cancels or keeps only the account's data.
class MergeCurrencyStop extends MergeState {
  const MergeCurrencyStop({required this.phone, required this.account});

  final String phone;
  final String account;
}

/// The phone's records are in the account's vault; [pending] changes are still to be sent. Stays
/// here offline; a later run goes on.
class MergeUploading extends MergeState {
  const MergeUploading(this.pending);

  final int pending;
}

/// Everything is in the account and the anonymous user is deleted.
class MergeDone extends MergeState {
  const MergeDone();
}

/// A step failed ([code]: `offline`, `busy`, `account_plain`, the server's code, `server`).
/// [carried]: the phone's records are already in the account (only the upload and the delete are
/// left), so cancelling is no longer offered.
class MergeFailed extends MergeState {
  const MergeFailed(this.code, {this.carried = false});

  final String code;
  final bool carried;
}

/// Secure storage key of the anonymous session's token while its vault is merged (swept with
/// that vault's `wambito.vault.<anonId>.*` keys).
String mergeTokenKey(String anonId) => 'wambito.vault.$anonId.mergeToken';

/// The old vault's meta key set once the carry committed (an ISO instant).
const mergeCarriedMeta = 'mergeCarried';

/// The old vault's meta key set once "Keep only the account's data" was chosen (an ISO instant): a
/// later run finishes without carrying, and the currency stop never shows again.
const mergeDiscardMeta = 'mergeDiscard';

/// The account's open vault, which the phone's records go into.
class MergeTarget {
  const MergeTarget({
    required this.userId,
    required this.email,
    required this.store,
    required this.sync,
    required this.pendingChanges,
    required this.serverVersion,
  });

  final String userId;
  final String email;
  final FinanceStore store;

  /// One sync run; false when it stopped early (offline, a server error).
  final Future<bool> Function() sync;
  final Future<int> Function() pendingChanges;

  /// The server's version of a record in the vault: 0 until the server took it (a change it
  /// refused for good, `id_taken` or given up on, stays 0); null without the record.
  final Future<int?> Function(RecordType type, String id) serverVersion;
}

/// The signed-in `preview` account's open vault, once the gate is Ready, while a merge is on;
/// else null (without a merge the vault session is not touched).
final mergeTargetProvider = Provider<MergeTarget?>((ref) {
  final merge = ref.watch(mergeControllerProvider);
  if (merge is MergeIdle || merge is MergeDone) return null;
  final session = ref.watch(vaultSessionProvider);
  final account = ref.watch(currentVaultAccountProvider);
  if (session == null || account == null || account.profile.id != session.userId) return null;
  return MergeTarget(
    userId: session.userId,
    email: account.profile.email,
    store: session.store,
    sync: () async => (await session.sync()).ok,
    pendingChanges: session.pendingChanges,
    serverVersion: session.serverVersion,
  );
});

/// What a merge reaches on the phone; tests put their own folder in.
class MergeDeps {
  const MergeDeps({
    required this.listHolds,
    required this.openSource,
    required this.lease,
    required this.storage,
    required this.now,
  });

  final Future<({List<({String userId, VaultHold hold})> holds, List<String> unreadable})>
  Function()
  listHolds;

  /// The phone's old vault on a connection of its own (no session, no keys): closing it never
  /// closes the app's.
  final Future<SqliteStore> Function(String userId) openSource;

  /// The old vault's lease (lib/local/vault_lock.dart), so no headless run writes into it while
  /// the carry reads it; null when another holds it.
  final Future<VaultLease?> Function(String userId) lease;
  final FlutterSecureStorage storage;
  final DateTime Function() now;
}

final mergeDepsProvider = Provider<MergeDeps>(
  (ref) => MergeDeps(
    listHolds: listVaultHolds,
    openSource: (id) => SqliteStore.open(id, background: true),
    lease: (id) => waitLease(id, holder: 'app', wait: appLeaseWait),
    storage: appSecureStorage,
    now: DateTime.now,
  ),
);

typedef _Job = ({String anonId, String email, String token});

bool _sameEmail(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

String _codeOf(Object error) => switch (error) {
  AuthFailure(status: 0) => 'offline',
  AuthFailure(:final code?) => code,
  _ => 'server',
};

class MergeController extends Notifier<MergeState> {
  _Job? _job;
  var _busy = false;

  MergeDeps get _deps => ref.read(mergeDepsProvider);

  /// The phone's own account id while a merge is on: a merge's sign-in passes it to
  /// `SessionController.verifyCode(keepCapturesOf:)` (the session also finds it by itself through
  /// [mergeSignInProvider]).
  String? get guestUserId => _job?.anonId;

  void _follow(_Job? job) {
    ref.read(mergeSignInProvider)
      ..email = job?.email
      ..guestUserId = job?.anonId;
  }

  @override
  MergeState build() => const MergeIdle();

  /// "Bring this phone's data into it?" said yes: the signed-in `preview` account without email
  /// holds its vault (`merging`, target [email]) and keeps its token, before any code is sent. The
  /// caller then sends the email's code with `replaceGuest: true`.
  Future<void> begin(String email) async {
    final account = ref.read(currentVaultAccountProvider);
    final token = ref.read(sessionProvider).stored?.token;
    if (account == null ||
        token == null ||
        account.mode != EncryptionMode.preview ||
        !account.profile.isAnonymous) {
      throw StateError('Only a preview account without email merges');
    }
    final anonId = account.profile.id;
    // The token first: a hold without it could never delete the anonymous user.
    await _deps.storage.write(key: mergeTokenKey(anonId), value: token);
    await _withSource(anonId, (source) async {
      // What an earlier merge of this vault left goes: this one starts from nothing.
      await source.setMeta(mergeCarriedMeta, null);
      await source.setMeta(mergeDiscardMeta, null);
      await source.setHold(
        VaultHold(
          VaultHoldKind.merging,
          target: email,
          since: _deps.now().toUtc().toIso8601String(),
        ),
      );
    });
    _job = (anonId: anonId, email: email, token: token);
    _follow(_job);
    state = MergeSigningIn(email);
  }

  /// Picks a merge up from the phone's vaults (`listVaultHolds`) at start, and follows the signed-in
  /// account: still the phone's own session, the sign-in is still to come (the hold stays); the
  /// email account, its vault is to be unlocked. A vault whose hold cannot be read, or a hold without its
  /// token, is left as it is (the sweep keeps it too): nothing of the person's is dropped on a guess.
  Future<void> resume() async {
    if (_busy) return;
    final account = ref.read(currentVaultAccountProvider);
    if (account == null) return;
    var job = _job;
    if (job == null) {
      final found = await _deps.listHolds();
      final held = found.holds
          .where((h) => h.hold.kind == VaultHoldKind.merging && h.hold.target != null)
          .firstOrNull;
      if (held == null) return;
      final token = await _deps.storage.read(key: mergeTokenKey(held.userId));
      if (token == null) return;
      if (!ref.mounted || _job != null) return;
      job = _job = (anonId: held.userId, email: held.hold.target!, token: token);
      _follow(job);
    }
    if (account.profile.id == job.anonId) {
      // Still the phone's own session: the code (or the email's link, which may come after a
      // restart) is still to be used. The hold stays until the sign-in or a cancel.
      if (state is! MergeSigningIn) state = MergeSigningIn(job.email);
      return;
    }
    if (!_sameEmail(account.profile.email, job.email)) return;
    if (account.mode == EncryptionMode.plain) {
      // Nothing can be carried into an account that keeps no encrypted data: cancel only.
      state = const MergeFailed('account_plain');
      return;
    }
    if (state is MergeIdle || state is MergeSigningIn) state = const MergeWaitingUnlock();
  }

  /// Once the account's vault is open ([mergeTargetProvider]): the currency check, the carry
  /// (once: `meta.mergeCarried`), the upload until the outbox is empty, then the anonymous user's
  /// `DELETE /v1/me` and the old vault forgotten. Offline it stays [MergeUploading]; run it again.
  Future<void> run() async {
    final job = _job;
    if (job == null || _busy || state is MergeCurrencyStop || state is MergeDone) return;
    if (state is MergeSigningIn) return;
    // Through the container: the target watches this notifier, so a `ref.read` of it here is a
    // dependency loop to riverpod's debug-mode check (it threw, and debug builds never merged).
    final target = ref.container.read(mergeTargetProvider);
    if (target == null || target.userId == job.anonId || !_sameEmail(target.email, job.email)) {
      return;
    }
    _busy = true;
    var carried = false;
    try {
      final source = await _deps.openSource(job.anonId);
      final List<(RecordType, String)> kept;
      try {
        if (await source.getMeta(mergeDiscardMeta) != null) {
          await source.close();
          await _finish(job);
          return;
        }
        carried =
            await source.getMeta(mergeCarriedMeta) != null || await _committed(source, target);
        if (!carried) {
          final lease = await _deps.lease(job.anonId);
          if (lease == null) {
            state = const MergeFailed('busy');
            return;
          }
          try {
            final phone = await currencyOf(source);
            final account = await currencyOf(target.store);
            if (phone != null && account != null && phone != account) {
              state = MergeCurrencyStop(phone: phone, account: account);
              return;
            }
            await carryRecords(
              source,
              target.store,
              mode: CarryMode.merge,
              intoUserId: target.userId,
            );
            carried = true;
          } finally {
            await lease.release();
          }
        }
        // Also after a crash between the carry's commit and this mark: [_committed] saw it.
        await source.setMeta(mergeCarriedMeta, _deps.now().toUtc().toIso8601String());
        kept = await _keptIds(source, target);
      } finally {
        if (!source.isClosed) await source.close();
      }
      // From here no session names the old vault (the token is the account's): nothing writes
      // into it before it is forgotten.
      await _upload(job, target, kept);
    } on Object catch (error) {
      if (ref.mounted) state = MergeFailed(_codeOf(error), carried: carried);
    } finally {
      _busy = false;
    }
  }

  /// The ids the carry gives the phone's records ([mergedIdsOf]) that the account's vault holds.
  Future<List<(RecordType, String)>> _keptIds(SqliteStore source, MergeTarget target) async => [
    for (final (type, id) in await mergedIdsOf(source, target.userId))
      if (await target.store.get(type, id, const ReadOptions(includeDeleted: true)) != null)
        (type, id),
  ];

  /// Whether the carry already committed: one of the ids it gives the phone's records is in the
  /// account's vault (they derive from the account and the phone's own ids, so nothing else has
  /// them).
  Future<bool> _committed(SqliteStore source, MergeTarget target) async =>
      (await _keptIds(source, target)).isNotEmpty;

  Future<void> _upload(_Job job, MergeTarget target, List<(RecordType, String)> kept) async {
    // `pendingChanges` leaves out re-seals (the server already has those records) and changes the
    // sync gave up on; the latter, and an `id_taken` the sync drops, are caught below: every carried
    // record must have a server version before the anonymous user goes.
    var pending = await target.pendingChanges();
    state = MergeUploading(pending);
    while (pending > 0) {
      final ok = await target.sync();
      final left = await target.pendingChanges();
      if (!ref.mounted) return;
      state = MergeUploading(left);
      if (left == 0) break;
      // Offline, or nothing moved: the next run goes on.
      if (!ok || left >= pending) return;
      pending = left;
    }
    for (final (type, id) in kept) {
      if ((await target.serverVersion(type, id) ?? 0) == 0) {
        // The server will not take it: the anonymous user (and its copy on the server) stays.
        state = const MergeFailed('refused', carried: true);
        return;
      }
    }
    await _finish(job);
  }

  /// The anonymous user goes on the server (`deleteUser`: a 401 is already gone), then its vault,
  /// its keys and the kept token here.
  Future<void> _finish(_Job job) async {
    await ref.read(authApiProvider).deleteUser(job.token);
    await ref.read(forgetVaultProvider)(job.anonId, ref.read(keyStorageProvider));
    await _deps.storage.delete(key: mergeTokenKey(job.anonId));
    await _deps.storage.delete(key: EncryptionStore.modeKey(job.anonId));
    _job = null;
    _follow(null);
    if (ref.mounted) state = const MergeDone();
  }

  /// Calls the merge off (ruling 10, confirmed by the founder): after the email sign-in, this phone
  /// signs out of the email account and the anonymous session is back with its data
  /// ([SessionController.returnToGuest]); before it, only the hold goes. Then the hold and the kept
  /// token go. Not once the records are carried (the account has them).
  Future<void> cancel() async {
    final job = _job;
    if (job == null) {
      state = const MergeIdle();
      return;
    }
    if (_busy) return;
    final carried = await _withSource(
      job.anonId,
      (source) async => await source.getMeta(mergeCarriedMeta) != null,
    );
    // ("Keep only the account's data" chosen and its delete failed: cancelling is still possible,
    // nothing was deleted; the next `begin` clears the mark.)
    if (carried) throw StateError('The records are already in the account');
    if (ref.read(sessionProvider).stored?.token != job.token) {
      await ref.read(sessionProvider.notifier).returnToGuest(job.token, guestUserId: job.anonId);
    }
    // After the guest session is back: until then the hold keeps the vault through any sweep.
    await _clear(job);
    if (ref.mounted) state = const MergeIdle();
  }

  /// "Keep only the account's data" (after its confirm): nothing is carried; the anonymous user and
  /// its vault are deleted.
  Future<void> keepAccountOnly() async {
    final job = _job;
    if (job == null || _busy) return;
    if (ref.read(sessionProvider).stored?.token == job.token) {
      throw StateError('Not signed in to the account');
    }
    _busy = true;
    try {
      // Kept in the old vault before the delete: a later run (after a crash or a failure) finishes
      // the same way and never shows the currency stop again.
      await _withSource(
        job.anonId,
        (source) => source.setMeta(mergeDiscardMeta, _deps.now().toUtc().toIso8601String()),
      );
      await _finish(job);
    } on Object catch (error) {
      if (ref.mounted) state = MergeFailed(_codeOf(error));
    } finally {
      _busy = false;
    }
  }

  Future<void> _clear(_Job job) async {
    await _withSource(job.anonId, (source) => source.setHold(null));
    await _deps.storage.delete(key: mergeTokenKey(job.anonId));
    if (identical(_job, job)) {
      _job = null;
      _follow(null);
    }
  }

  Future<T> _withSource<T>(String anonId, Future<T> Function(SqliteStore source) use) async {
    final source = await _deps.openSource(anonId);
    try {
      return await use(source);
    } finally {
      await source.close();
    }
  }
}

final mergeControllerProvider = NotifierProvider<MergeController, MergeState>(MergeController.new);

/// Whether the app stays on `/merge` (lib/router.dart): while the phone's records wait for the
/// account's open vault, at the currency stop, and after a failure before the carry. Once carried,
/// the person may use the account while the upload goes on.
final mergeBlocksAppProvider = Provider<bool>((ref) {
  final state = ref.watch(mergeControllerProvider);
  return state is MergeWaitingUnlock ||
      state is MergeCurrencyStop ||
      (state is MergeFailed && !state.carried);
});

/// The merge's start and resume hook (app.dart, after the adoption's and before the seen ping):
/// [MergeController.resume] when the signed-in account is known or changes and when the app comes
/// back, then [MergeController.run]; and a run as soon as the account's vault opens.
final mergeResumeProvider = Provider<void>((ref) {
  final merge = ref.read(mergeControllerProvider.notifier);
  void resume() {
    unawaited(merge.resume().then((_) => merge.run()).catchError((Object _) {}));
  }

  ref.listen(currentVaultAccountProvider.select((a) => (a?.owner, a?.profile.id, a?.mode)), (
    _,
    next,
  ) {
    if (next.$1 != null) resume();
  }, fireImmediately: true);
  ref.listen(mergeTargetProvider, (_, next) {
    if (next != null) unawaited(merge.run().catchError((Object _) {}));
  });
  final observer = _ResumeObserver(resume);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});

/// A [WidgetsBindingObserver] (not an `AppLifecycleListener`, as the seen ping's).
class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this._onResume);

  final void Function() _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }
}
