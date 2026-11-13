import 'dart:async';

import 'package:dio/dio.dart';

import '../core/schemas.dart' show supportedLocales;
import '../core/suggested_categories.dart';
import '../crypto/records.dart' show RecordType;
import 'backend.dart';
import 'backend_interceptor.dart';
import 'ids.dart';
import 'keys.dart';
import 'sqlite_store.dart';
import 'sync.dart';

/// A preview account's open vault on this phone: the Dart twin of
/// `apps/web/app/local/vault-session.ts`. It ties the store, the keys, the local backend the
/// screens' requests go to (through [VaultSession.interceptor]) and the sync engine into one
/// session, one per account in the process, until sign-out, a 401 or a removal ends it.
///
/// Phone differences: the session hands out a Dio [Interceptor] instead of a `fetch`, its keys live
/// in [KeyStorage], [forgetVault] takes the account (the web's uses the tab's), and the vault file
/// is deleted by [forgetVault] (the web's `forgetDevice` deletes its IndexedDB vault). There is one
/// `SqliteStore` per account in the process: an open waits for the previous store of the same
/// account to finish closing.

/// What the server says about the account; the vault's profile and its first settings.
class VaultProfile {
  const VaultProfile({
    required this.id,
    required this.email,
    required this.isAnonymous,
    required this.locale,
    required this.timezone,
  });

  final String id;
  final String email;
  final bool isAnonymous;
  final String locale;
  final String timezone;
}

/// Opening failed; [code] says why (`offline` gets the offline copy).
class VaultOpenError implements Exception {
  const VaultOpenError(this.code);

  final SyncProblemCode code;

  @override
  String toString() => 'VaultOpenError(${code.wire})';
}

class OpenVaultOptions {
  const OpenVaultOptions({
    required this.profile,
    required this.keys,
    required this.fresh,
    required this.network,
    required this.storage,
    this.now,
    this.onUnauthorized,
    this.onSessionChanged,
    this.openStore,
    this.deleteStore,
    this.syncDebounce = const Duration(seconds: 1),
    this.refreshKeys,
  });

  final VaultProfile profile;
  final LocalKeys keys;

  /// The keys were just made or unlocked: the first full sync must succeed.
  final bool fresh;

  /// The network (base `<server>/api`, without the local interceptor), for `/v2` and the live
  /// routes.
  final Dio network;
  final KeyStorage storage;
  final DateTime Function()? now;

  /// The session is gone (a 401 from sync): the caller wipes the vault and goes to sign-in.
  final void Function()? onUnauthorized;

  /// The session now belongs to another account (409 `session_changed` from sync): the session has
  /// stopped and closed; the caller checks who is signed in.
  final void Function()? onSessionChanged;

  /// The store and its deletion; tests pass their own (a temp folder). Default: the app's vault.
  final Future<SqliteStore> Function(String userId)? openStore;
  final Future<void> Function(String userId)? deleteStore;

  /// The wait between a local write and its sync.
  final Duration syncDebounce;

  /// `keys.dart`'s `refreshKeys`; tests pass their own to hold or fail a refresh.
  final Future<LocalKeys> Function(KeysOptions options)? refreshKeys;
}

/// The open vault of one account.
class VaultSession {
  VaultSession._(this.userId, this.interceptor, this._store, this._engine, this._storage);

  final String userId;

  /// The `/v1/*` the screens use: answered by the local backend (`GET` and `PATCH /v1/me`
  /// included); deleting the account and everything outside `/v1` go on to the network. Its
  /// local writes start a sync.
  final Interceptor interceptor;
  final SqliteStore _store;
  final SyncEngine _engine;
  final KeyStorage _storage;
  final Set<void Function()> _closedListeners = {};
  final Set<void Function()> _removedListeners = {};
  final Set<void Function()> _unverifiedListeners = {};
  bool _closing = false;
  late final void Function() _drop;

  /// Called after every commit to the store (the screens refetch). Returns the unsubscribe.
  void Function() subscribe(void Function() listener) => _store.subscribe(listener);

  /// Called once if the vault closes under the session: the sync has stopped and the session is
  /// gone; the gate checks again.
  void Function() onClosed(void Function() listener) {
    _closedListeners.add(listener);
    return () => _closedListeners.remove(listener);
  }

  /// Called once if this phone was removed from the account (its device wrap is gone): the sync
  /// has stopped, the vault and the keys are deleted and the session is gone; the gate shows
  /// Unlock.
  void Function() onRemoved(void Function() listener) {
    _removedListeners.add(listener);
    return () => _removedListeners.remove(listener);
  }

  /// Called once if a new key version did not verify: the sync has stopped and the session is
  /// gone, but the vault and its unsent changes are kept; the gate shows Unlock.
  void Function() onUnverified(void Function() listener) {
    _unverifiedListeners.add(listener);
    return () => _unverifiedListeners.remove(listener);
  }

  /// A sync now (pull-to-refresh). Shares a run in flight.
  Future<SyncResult> sync() => _engine.run();

  /// After a rotation committed on this phone: gives the sync the keyring storage now holds, then
  /// runs a sync (its upgrade pass re-seals the old records).
  Future<void> reloadKeys() async {
    final local = await loadLocalKeys(userId, _storage);
    if (local != null) _engine.useKeyring(local.keyring);
    await _engine.run();
  }

  /// The person's changes not pushed yet (re-seals and given-up changes are not counted): the
  /// sign-out sheet's "You have N changes not synced yet".
  Future<int> pendingChanges() async =>
      (await _store.readOutbox(_all)).where((e) => !e.reseal && !e.abandoned).length;

  /// Stops the sync and closes the store; completes once the file is released.
  Future<void> close() {
    _closing = true;
    _drop();
    return _closeStore(userId, _store);
  }
}

const _all = 9007199254740991;

class _Active {
  _Active(this.userId);

  final String userId;
  VaultSession? session;

  /// An open in flight, shared by a second caller.
  Future<VaultSession>? opening;

  /// The store of the open in flight, so a sign-out during it can close it.
  SqliteStore? store;
  Future<void> Function(String userId)? deleteStore;

  /// Signed out: a late run must not leave anything behind.
  bool forgotten = false;
}

/// The account whose vault is open (or opening) in this process.
_Active? _active;

/// Stores closing, by account: the next open of the same account waits for the file.
final Map<String, Future<void>> _closings = {};

Future<void> _closeStore(String userId, SqliteStore store) {
  final closing = store.close();
  _closings[userId] = closing;
  unawaited(
    closing
        .whenComplete(() {
          if (identical(_closings[userId], closing)) _closings.remove(userId);
        })
        .catchError((Object _) {}),
  );
  return closing;
}

Future<void> _defaultDelete(String userId) => deleteVault(userId);

/// Whether a wipe by account id (the vault file, the keys) still belongs to [mine]: no newer open
/// of the same account exists in the process.
bool _mayWipe(_Active mine) {
  final current = _active;
  return current == null || identical(current, mine) || current.userId != mine.userId;
}

/// The namespace of the seeded records' ids; the account's own namespace is made from it.
const _seedNamespace = '6f1f7a4e-0c5b-5e0a-9a3e-2b1d6c8f4a10';

/// Creates the account's first records when it has none after the first sync: the settings (from
/// the server's profile, the web's default currency EUR) and the suggested categories in the
/// person's language. The ids are UUID v5 of the account and the record's name, and the content
/// comes from the profile only, so two devices seeding at once write the same records.
Future<void> _seedIfEmpty(SqliteStore store, VaultProfile profile) async {
  if ((await store.list(RecordType.settings)).isNotEmpty) return;
  final locale = supportedLocales.contains(profile.locale) ? profile.locale : 'es';
  final names = SuggestionLocale.values.byName(locale);
  final namespace = uuidv5(_seedNamespace, profile.id);
  final settingsId = uuidv5(namespace, 'settings');
  final categories = [
    for (final (i, s) in suggestedCategories.indexed)
      (
        id: uuidv5(namespace, 'category:${s.key}'),
        body: <String, Object?>{
          's': 1,
          'name': s.names[names],
          'kind': s.kind.name,
          'icon': s.glyph,
          'color': s.tint,
          'sortOrder': i,
          'archivedAt': null,
          'systemKey': null,
        },
      ),
  ];
  await store.transaction((tx) async {
    await tx.put(RecordType.settings, settingsId, <String, Object?>{
      's': 1,
      'name': null,
      'currency': 'EUR',
      'locale': locale,
      'timezone': profile.timezone,
      'onboardingCompletedAt': null,
      'revokedDevices': <Object?>[],
    });
    for (final (:id, :body) in categories) {
      await tx.put(RecordType.category, id, body);
    }
  });
}

/// Opens (or reuses) the account's vault session: the store, a full sync (required when `fresh`;
/// a known phone opens on its local data when offline), the first records if the account has
/// none, then the sync's triggers.
Future<VaultSession> openVaultSession(OpenVaultOptions options) {
  final id = options.profile.id;
  final current = _active;
  if (current != null && current.userId == id && !current.forgotten) {
    final session = current.session;
    if (session != null) return Future.value(session);
    final opening = current.opening;
    if (opening != null) return opening;
  }
  if (current == null || current.userId != id || current.forgotten) {
    final previous = current?.session;
    if (previous != null) unawaited(previous.close());
    _active = _Active(id);
  }
  final mine = _active!..deleteStore = options.deleteStore;
  late final Future<VaultSession> opening;
  opening = _open(options, mine).whenComplete(() {
    if (identical(mine.opening, opening)) mine.opening = null;
  });
  mine.opening = opening;
  return opening;
}

Future<VaultSession> _open(OpenVaultOptions options, _Active mine) async {
  final profile = options.profile;
  final userId = profile.id;
  final storage = options.storage;
  final network = options.network;
  final deleteStore = options.deleteStore ?? _defaultDelete;
  await _closings[userId];
  final store = await (options.openStore ?? SqliteStore.open)(userId);
  mine.store = store;
  if (mine.forgotten) {
    // Signed out while the file was opening: it goes again.
    await _closeStore(userId, store);
    await deleteStore(userId);
    throw const VaultOpenError(SyncProblemCode.closed);
  }
  try {
    final backend = createLocalBackend(
      store: store,
      now: options.now ?? DateTime.now,
      unavailable: localUnavailable,
      timezone: profile.timezone,
      profile: LocalProfile(
        id: profile.id,
        email: profile.email,
        isAnonymous: profile.isAnonymous,
        encryption: 'preview',
      ),
    );
    // Set once open: a later 409 `session_changed` closes it, `device_removed` removes it,
    // `key_unverified` closes it and keeps the vault.
    VaultSession? opened;
    void Function()? removed;
    void Function()? unverified;
    final engine = createSyncEngine(
      SyncEngineOptions(
        store: store,
        dio: network,
        userId: userId,
        keyring: options.keys.keyring,
        refreshKeys: () async {
          if (mine.forgotten) throw const VaultClosedError();
          final LocalKeys local;
          try {
            local = await (options.refreshKeys ?? refreshKeys)(
              KeysOptions(userId: userId, dio: network, storage: storage),
            );
          } on Object {
            // Signed out while it ran: its failure is the old session's, never reported.
            if (mine.forgotten) throw const VaultClosedError();
            rethrow;
          }
          if (mine.forgotten) {
            // Signed out while the refresh ran: whatever it kept goes too, unless the account is
            // open (or opening) again, whose keys these now are.
            if (_mayWipe(mine)) await forgetDevice(userId, storage);
            throw const VaultClosedError();
          }
          return local.keyring;
        },
        dropKeyVersion: (v) => dropKeyVersion(userId, v, storage),
        debounce: options.syncDebounce,
        onError: (problem) {
          // A signed-out or closing session tells nobody anything (a late run of it ends here).
          if (mine.forgotten || (opened?._closing ?? false)) return;
          switch (problem.code) {
            case SyncProblemCode.unauthorized:
              options.onUnauthorized?.call();
            case SyncProblemCode.sessionChanged:
              final session = opened;
              if (session != null) {
                unawaited(session.close());
                options.onSessionChanged?.call();
              }
            case SyncProblemCode.deviceRemoved:
              removed?.call();
            case SyncProblemCode.keyUnverified:
              unverified?.call();
            default:
              break;
          }
        },
      ),
    );
    final first = await engine.run();
    if (first.problem == SyncProblemCode.deviceRemoved) {
      await _closeStore(userId, store);
      if (_mayWipe(mine)) {
        await deleteStore(userId);
        await forgetDevice(userId, storage);
      }
      throw const VaultOpenError(SyncProblemCode.deviceRemoved);
    }
    // Never opened on a key version that did not verify; the vault stays (the catch closes it).
    if (first.problem == SyncProblemCode.keyUnverified) {
      throw const VaultOpenError(SyncProblemCode.keyUnverified);
    }
    final fatal =
        first.error == SyncProblemCode.unauthorized ||
        first.error == SyncProblemCode.sessionChanged;
    if (!first.ok && (options.fresh || fatal)) {
      throw VaultOpenError(first.error ?? SyncProblemCode.server);
    }
    if (mine.forgotten || store.isClosed) throw const VaultOpenError(SyncProblemCode.closed);
    // Only on a complete first sync: an empty-looking vault may just be one not downloaded yet
    // (offline, or a resync whose set-aside changes still wait for their download).
    final waiting = (await store.readOutbox(_all)).any((e) => e.setAside != null);
    if (first.ok && !waiting) await _seedIfEmpty(store, profile);

    final session = VaultSession._(
      userId,
      LocalBackendInterceptor(backend, afterWrite: engine.afterLocalWrite),
      store,
      engine,
      storage,
    );
    session._drop = () {
      engine.stop();
      if (identical(_active?.session, session)) _active!.session = null;
    };
    // Every store op now throws `VaultClosedError`: stop, forget the session, tell the gate.
    store.onClosed(() {
      if (session._closing) return;
      session._drop();
      for (final listener in List.of(session._closedListeners)) {
        listener();
      }
    });
    // This phone's device wrap is gone: stop, delete the vault and its keys, tell the gate.
    removed = () {
      removed = null;
      unawaited(() async {
        try {
          await session.close();
        } on Object {
          // closed or not, the vault goes and the gate is told
        }
        try {
          // Only while the vault is still this session's (a sign-out may have come first).
          if (_mayWipe(mine)) {
            await deleteStore(userId);
            await forgetDevice(userId, storage);
          }
        } on Object {
          // the gate still shows Unlock; sign-out deletes them again
        }
        for (final listener in List.of(session._removedListeners)) {
          listener();
        }
      }());
    };
    // A new key version did not verify: stop and close, keep the vault (never forget the keys).
    unverified = () {
      unverified = null;
      unawaited(session.close());
      for (final listener in List.of(session._unverifiedListeners)) {
        listener();
      }
    };
    if (identical(_active, mine)) mine.session = session;
    opened = session;
    engine.start();
    return session;
  } on Object {
    await _closeStore(userId, store);
    rethrow;
  }
}

/// Sign-out (and a lost session): stops the sync, closes the store, deletes the vault file of
/// [userId] and every one of its keys. A run still in flight ends `closed` and writes nothing.
/// [deleteStore] is for tests (default: the open session's, else the app's vault).
Future<void> forgetVault(
  String userId,
  KeyStorage storage, {
  Future<void> Function(String userId)? deleteStore,
}) async {
  var delete = deleteStore;
  final current = _active;
  if (current != null && current.userId == userId) {
    _active = null;
    current.forgotten = true;
    delete ??= current.deleteStore;
    final session = current.session;
    final store = current.store;
    if (session != null) {
      await session.close();
    } else if (store != null) {
      await _closeStore(userId, store);
    }
  }
  await _closings[userId];
  await (delete ?? _defaultDelete)(userId);
  await forgetDevice(userId, storage);
}
