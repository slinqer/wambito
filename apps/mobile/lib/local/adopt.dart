// Adopting a vault into a new user (phone-first spec 10 step 3, ruling 7): the deleted user's
// vault (`adoptOrphan`, here) and the offline start's provisional vault (Task 11) both go through
// [adoptVaultIntoNewUser]. Its records are carried as they are (`carryRecords(mode: adopt)`, the
// ids kept: the old user's records are gone from the server, or never reached it) into the new
// user's vault as new local writes, so the outbox pushes each one sealed under the new user's id and
// data key, with no base version. The old vault stays held until it is forgotten, and the new
// user's token is kept before anything else, so a crash anywhere resumes without a second user.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show DatabaseFactory;

import '../api/auth_api.dart';
import '../crypto/records.dart' show RecordType;
import 'db.dart'
    show VaultHold, VaultHoldKind, defaultVaultDirectory, listVaultHolds, vaultFileName;
import 'keys.dart';
import 'merge.dart' show CarryMode, carryRecords;
import 'sqlite_store.dart';
import 'store.dart' show FinanceStore;
import 'vault_lock.dart' show VaultLease;

/// Where [adoptVaultIntoNewUser] stopped.
enum AdoptStep {
  /// The records are in the new user's vault and the old vault is forgotten.
  adopted,

  /// The new user is `plain` (the server keeps no encrypted data for new users): nothing was
  /// carried, the old vault stays held and the new user's token stays kept. The caller decides.
  plainUser,

  /// The server could not be reached (or could not answer): nothing is lost, run it again later.
  waiting,
}

/// How [adoptOrphan] ended.
enum AdoptOutcome {
  /// A new user has the deleted user's data; the session is the new user's.
  adopted,

  /// The deleted user's vault held no data (ruling 18): it was wiped and the phone signed out.
  wiped,

  /// Not now (offline, the vault's lease held by a headless run, a `plain` new user): the vault
  /// stays held and the next start or resume goes on.
  waiting,
}

/// What an adoption reaches; tests pass their own folder, servers and storage.
class AdoptDeps {
  const AdoptDeps({
    required this.auth,
    required this.keys,
    required this.network,
    required this.openStore,
    required this.lease,
    required this.forgetVault,
    required this.now,
    required this.keptToken,
    required this.keepToken,
    required this.forgetToken,
    this.directory,
    this.factory,
    this.stopWrites,
    this.onAdopted,
    this.onWiped,
    this.mayResume,
    this.hasQueuedCaptures,
    this.listHolds,
    this.onStep,
  });

  /// `POST /auth/sign-in/anonymous`, `GET /v1/me`, `DELETE /v1/me`.
  final AuthApi auth;

  /// Where the new user's keys are kept (`prepareAccount`).
  final KeyStorage keys;

  /// The network for `/v2/keys` with [token]'s bearer (base `<server>/api`).
  final Dio Function(String token) network;

  /// A vault on a connection of its own (`SqliteStore.open(id, background: true)`): the old one
  /// and the new user's.
  final Future<SqliteStore> Function(String userId) openStore;

  /// The old vault's lease (lib/local/vault_lock.dart), held from the carry's read until the old
  /// vault is forgotten, so no headless capture writes into it meanwhile; null when another holds it.
  final Future<VaultLease?> Function(String userId) lease;

  /// Deletes a vault's file and keys (`forgetVault`).
  final Future<void> Function(String userId) forgetVault;
  final DateTime Function() now;

  /// The new user's token, kept before anything is made for it ([keepToken]): a run after a crash
  /// reuses it instead of making a second user. [forgetToken] once the session is the new user's.
  final Future<String?> Function() keptToken;
  final Future<void> Function(String token) keepToken;
  final Future<void> Function() forgetToken;

  /// The vault folder and the database factory (tests); default: the app's.
  final String? directory;
  final DatabaseFactory? factory;

  /// Closes whatever in the app still writes into the old vault (its open vault session), right
  /// before the carry reads it.
  final Future<void> Function(String userId)? stopWrites;

  /// [adoptOrphan] adopted: the session becomes the new user's ([token]), taking over [fromUserId]'s
  /// queued captures.
  final Future<void> Function(String token, {required String fromUserId})? onAdopted;

  /// [adoptOrphan] wiped [oldUserId]'s empty vault: the session of that account signs out.
  final Future<void> Function(String oldUserId)? onWiped;

  /// Whether [resumeAdoption] may go on with [oldUserId]'s held vault now: the phone is signed out,
  /// or still in that account's session. Another account's session is never replaced by it.
  final Future<bool> Function(String oldUserId)? mayResume;

  /// Whether captures detected from bank notifications still wait, unsaved, for [userId]
  /// (Android's queue): they are the person's data too, so a vault without records but with them
  /// is adopted, never wiped. Null: none can wait.
  final Future<bool> Function(String userId)? hasQueuedCaptures;

  /// [listVaultHolds] (tests put their own in).
  final Future<({List<({String userId, VaultHold hold})> holds, List<String> unreadable})>
  Function()?
  listHolds;

  /// Where each [adoptOrphan]'s routine stopped (the gate says why it waits: a `plain` new user).
  final void Function(AdoptStep step)? onStep;

  /// These deps with the session's part.
  AdoptDeps withSession({
    Future<void> Function(String token, {required String fromUserId})? onAdopted,
    Future<void> Function(String oldUserId)? onWiped,
    Future<bool> Function(String oldUserId)? mayResume,
    void Function(AdoptStep step)? onStep,
  }) => AdoptDeps(
    auth: auth,
    keys: keys,
    network: network,
    openStore: openStore,
    lease: lease,
    forgetVault: forgetVault,
    now: now,
    keptToken: keptToken,
    keepToken: keepToken,
    forgetToken: forgetToken,
    directory: directory,
    factory: factory,
    stopWrites: stopWrites,
    onAdopted: onAdopted ?? this.onAdopted,
    onWiped: onWiped ?? this.onWiped,
    mayResume: mayResume ?? this.mayResume,
    hasQueuedCaptures: hasQueuedCaptures,
    listHolds: listHolds,
    onStep: onStep ?? this.onStep,
  );
}

/// Whether [store] holds the person's data (ruling 18): any live movement, recurrence, budget or
/// merchant. Seeded settings and categories alone are not data.
Future<bool> vaultHoldsData(FinanceStore store) async {
  for (final type in const [
    RecordType.transaction,
    RecordType.recurrence,
    RecordType.budget,
    RecordType.merchant,
  ]) {
    if ((await store.list(type)).isNotEmpty) return true;
  }
  return false;
}

Future<bool> _vaultExists(String userId, AdoptDeps deps) async =>
    File(p.join(deps.directory ?? await defaultVaultDirectory(), vaultFileName(userId)))
        .existsSync();

/// A failure that only means "not now": no network, a server that could not answer.
bool _notNow(Object error) => switch (error) {
  AuthFailure(:final status) => status == 0 || status >= 500,
  KeysError(code: 'offline') => true,
  KeysError(code: 'server', :final status) => status == null || status >= 500,
  DioException() => true,
  _ => false,
};

Future<T> _withStore<T>(String userId, AdoptDeps deps, Future<T> Function(SqliteStore) use) async {
  final store = await deps.openStore(userId);
  try {
    return await use(store);
  } finally {
    if (!store.isClosed) await store.close();
  }
}

/// The shared adoption (ruling 7; Task 11 reuses it unchanged). In order, each step safe to run
/// again after a crash:
/// 1. the new user's token: one already kept ([AdoptDeps.keptToken]) is reused while it still
///    signs in (and is not another vault's: the hold's target names its user); else a new
///    anonymous user, whose token is kept at once ([AdoptDeps.keepToken]);
/// 2. the old vault's hold gets the new user's id as its target (its kind kept, `orphaned` when it
///    had none);
/// 3. a `plain` new user stops here: [AdoptStep.plainUser];
/// 4. the new user's keys, kept on this phone (`prepareAccount(guest: true)`: a hidden recovery
///    wrap, no key shown; the nudges start over), or the ones a crashed run already kept;
/// 5. under the old vault's lease, the app's writes into it stopped: `carryRecords(adopt)` into the
///    new user's vault (opened on its own, with nothing seeded), then the old vault forgotten.
/// No network (or a server that cannot answer) before step 5: [AdoptStep.waiting]. Without an old
/// vault file (a crash after step 5) it only checks the new user and its keys: [AdoptStep.adopted].
Future<AdoptStep> adoptVaultIntoNewUser(String oldVaultId, AdoptDeps deps) =>
    _adopt(oldVaultId, deps, again: true);

Future<AdoptStep> _adopt(String oldVaultId, AdoptDeps deps, {required bool again}) async {
  final hasVault = await _vaultExists(oldVaultId, deps);
  final hold = hasVault ? await _withStore(oldVaultId, deps, (s) => s.hold()) : null;

  // 1. The new user's token, kept before anything is made for it.
  String? token = await deps.keptToken();
  AccountStanding? standing;
  try {
    if (token != null) {
      try {
        standing = await deps.auth.standing(token);
        final target = hold?.target;
        // Kept for another vault's adoption: this one gets its own user.
        if (target != null && standing.userId != null && standing.userId != target) {
          token = null;
          standing = null;
        }
      } on AuthFailure catch (failure) {
        // That user's session is gone (it can never be signed in again): a new one.
        if (failure.status != 401) rethrow;
        token = null;
      }
    }
    if (token == null) {
      token = await deps.auth.signInAsGuest();
      await deps.keepToken(token);
      standing = await deps.auth.standing(token);
    }
  } on Object catch (error) {
    if (_notNow(error)) return AdoptStep.waiting;
    rethrow;
  }
  final newUserId = standing!.userId;
  if (newUserId == null) return AdoptStep.waiting;

  // 2. The hold names the new user: the sweep its `/v1/me` runs keeps the old vault.
  if (hasVault && hold?.target != newUserId) {
    await _withStore(
      oldVaultId,
      deps,
      (s) => s.setHold(
        VaultHold(
          hold?.kind ?? VaultHoldKind.orphaned,
          target: newUserId,
          since: hold?.since ?? deps.now().toUtc().toIso8601String(),
        ),
      ),
    );
  }

  // 3. Nothing is ever carried into a user whose data the server keeps in clear.
  if (!standing.encrypted) return AdoptStep.plainUser;

  // 4. The new user's keys: made once, kept on this phone.
  if (await loadLocalKeys(newUserId, deps.keys) == null) {
    try {
      final prepared = await prepareAccount(
        KeysOptions(userId: newUserId, dio: deps.network(token), storage: deps.keys),
        guest: true,
      );
      await prepared.commit();
    } on KeysError catch (error) {
      if (_notNow(error)) return AdoptStep.waiting;
      // The new user has keys this phone never kept (a crash between their upload and keeping
      // them): nobody can open that user's data, and it has none yet. Another user, once.
      if (error.code == 'already_set_up' && again) {
        try {
          await deps.auth.deleteUser(token);
        } on Object {
          // An empty anonymous user; the inactivity cleanup takes it.
        }
        await deps.forgetToken();
        return _adopt(oldVaultId, deps, again: false);
      }
      rethrow;
    }
  }

  // 5. The carry, under the old vault's lease, then the old vault goes.
  if (!hasVault) return AdoptStep.adopted;
  final lease = await deps.lease(oldVaultId);
  if (lease == null) return AdoptStep.waiting;
  try {
    await deps.stopWrites?.call(oldVaultId);
    await _withStore(oldVaultId, deps, (source) async {
      await _withStore(newUserId, deps, (target) async {
        await carryRecords(source, target, mode: CarryMode.adopt, intoUserId: newUserId);
      });
    });
    await deps.forgetVault(oldVaultId);
  } finally {
    await lease.release();
  }
  return AdoptStep.adopted;
}

/// A `user_deleted` 401 (phone-first spec 10 steps 1 to 3): the vault of [oldUserId] is held
/// `orphaned` first (the sweep keeps it); without data (ruling 18: no record, and no capture still
/// queued for it, [AdoptDeps.hasQueuedCaptures]) and with no adoption under way,
/// it is wiped and the phone signs out ([AdoptDeps.onWiped]); else [adoptVaultIntoNewUser], then
/// the session becomes the new user's ([AdoptDeps.onAdopted]) and the kept token goes. A vault
/// whose hold cannot be read is left as it is (it throws): nothing is wiped on a guess.
Future<AdoptOutcome> adoptOrphan(String oldUserId, AdoptDeps deps) async {
  final kept = await deps.keptToken();
  // Captures waiting in the queue are data too (never dropped): with any, the vault is adopted.
  Future<bool> queued() async {
    try {
      return await deps.hasQueuedCaptures?.call(oldUserId) ?? false;
    } on Object {
      return true; // Android could not read its queue: the safe side keeps them.
    }
  }

  if (await _vaultExists(oldUserId, deps)) {
    final empty = await _withStore(oldUserId, deps, (store) async {
      final hold = await store.hold();
      // Another kind (a merge whose anonymous user the cleanup deleted) becomes an adoption: that
      // user is gone, so only a new one can keep the data.
      if (hold?.kind != VaultHoldKind.orphaned) {
        await store.setHold(
          VaultHold(VaultHoldKind.orphaned, since: deps.now().toUtc().toIso8601String()),
        );
      }
      return !await vaultHoldsData(store);
    });
    if (empty && kept == null && !await queued()) {
      await deps.forgetVault(oldUserId);
      await deps.onWiped?.call(oldUserId);
      return AdoptOutcome.wiped;
    }
  } else if (kept == null && !await queued()) {
    // No vault here, no adoption under way, no capture waiting: nothing of the person's to keep.
    await deps.onWiped?.call(oldUserId);
    return AdoptOutcome.wiped;
  }
  final step = await adoptVaultIntoNewUser(oldUserId, deps);
  deps.onStep?.call(step);
  if (step != AdoptStep.adopted) return AdoptOutcome.waiting;
  final token = await deps.keptToken();
  if (token == null) return AdoptOutcome.waiting;
  await deps.onAdopted?.call(token, fromUserId: oldUserId);
  await deps.forgetToken();
  return AdoptOutcome.adopted;
}

/// At start and on resume: an `orphaned` vault ([listVaultHolds]) whose adoption did not finish (a
/// crash, no network) goes on, when [AdoptDeps.mayResume] allows it. A vault whose hold cannot be
/// read (`unreadable`) is left alone, never adopted nor deleted (the sweep keeps it too): it waits
/// for a build that can read it.
Future<void> resumeAdoption(AdoptDeps deps) async {
  final found =
      await (deps.listHolds ??
          () => listVaultHolds(directory: deps.directory, factory: deps.factory))();
  for (final (:userId, :hold) in found.holds) {
    if (hold.kind != VaultHoldKind.orphaned) continue;
    if (!(await deps.mayResume?.call(userId) ?? true)) continue;
    await adoptOrphan(userId, deps);
  }
}
