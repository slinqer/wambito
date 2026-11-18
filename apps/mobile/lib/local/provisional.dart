// The offline first run (phone-first spec 4, ruling 8): "Start" without network, on a server known
// to make encrypted users, opens a vault before any user exists. Its id is local (`local-<uuidv7>`),
// it is held `provisional` so no sweep takes it, and it is seeded from the phone's hints. Nothing in
// it is ever pushed or sealed: it has no keys and no sync engine. Once the network answers, the
// session promotes it (`SessionController.promoteProvisional`): `adoptVaultIntoNewUser` (Task 10)
// makes the anonymous user and carries the records into that user's vault.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show DatabaseFactory;

import '../api/device.dart';
import 'backend.dart';
import 'backend_interceptor.dart';
import 'db.dart' show VaultHold, VaultHoldKind;
import 'ids.dart';
import 'sqlite_store.dart';
import 'store.dart' show FinanceStore;
import 'vault_session.dart' show VaultProfile, seedIfEmpty;

/// A new provisional vault id: `local-` and a UUID v7, which the vault file pattern
/// (`wambito-vault-<id>.db`, `[A-Za-z0-9_-]{1,128}`) takes as it is.
String newProvisionalId([int? nowMs]) => 'local-${uuidv7(nowMs)}';

/// The vault of an offline first run, open in the app: the screens' `/v1` calls are answered by its
/// local backend ([interceptor]), and nothing else is done with it (no keys, no sync).
class LocalOnlyVault {
  LocalOnlyVault(
    this.localId,
    this.store, {
    String timezone = 'UTC',
    DateTime Function() now = DateTime.now,
    this.onClose,
  }) : interceptor = LocalBackendInterceptor(
         createLocalBackend(
           store: store,
           now: now,
           unavailable: localUnavailable,
           timezone: timezone,
           profile: LocalProfile(id: localId, isAnonymous: true, encryption: 'preview'),
         ),
       );

  final String localId;
  final FinanceStore store;

  /// Answers the `/v1` routes on the phone; what it does not answer goes on (the session's finance
  /// guard stops every finance call after it, so none reaches the network).
  final Interceptor interceptor;

  /// What [close] does (closing the store); tests pass their own.
  final Future<void> Function()? onClose;
  var _closed = false;

  bool get isClosed => _closed;

  /// Closes the store; the file stays (held) for the promotion. Safe to call twice.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await onClose?.call();
  }
}

/// The phone's language for the seed (`es-CO` is `es`); the seed falls back on Spanish.
String _language(String tag) => tag.split(RegExp('[-_]')).first.toLowerCase();

/// Opens (or reopens) the provisional vault [localId]: held `provisional` (once: a reopen keeps the
/// first hold), and seeded from [hints] (the settings and the suggested categories; a reopen seeds
/// nothing, `seedIfEmpty`). [directory] and [factory] are for tests.
Future<LocalOnlyVault> openProvisionalVault(
  String localId,
  DeviceHints hints, {
  String? directory,
  DatabaseFactory? factory,
  DateTime Function() now = DateTime.now,
}) async {
  final store = await SqliteStore.open(localId, directory: directory, factory: factory);
  try {
    if (await store.hold() == null) {
      await store.setHold(
        VaultHold(VaultHoldKind.provisional, since: now().toUtc().toIso8601String()),
      );
    }
    await seedIfEmpty(
      store,
      VaultProfile(
        id: localId,
        email: '',
        isAnonymous: true,
        locale: _language(hints.locale),
        timezone: hints.timezone,
      ),
    );
  } on Object {
    await store.close();
    rethrow;
  }
  return LocalOnlyVault(
    localId,
    store,
    timezone: hints.timezone,
    now: now,
    onClose: () async {
      if (!store.isClosed) await store.close();
    },
  );
}

/// Opens a provisional vault: [openProvisionalVault] with the phone's hints; tests put their own in.
final provisionalOpenerProvider = Provider<Future<LocalOnlyVault> Function(String localId)>(
  (ref) =>
      (localId) => openProvisionalVault(localId, ref.read(deviceHintsProvider)),
);

/// The provisional vault open in the app (null when none): the session opens it while it is
/// provisional ([open]) and the promotion stops it ([stop]) right before the carry reads it, so no
/// write lands in it afterwards; it never reopens while stopped (the gate's `refuseAdopted`, for a
/// vault held `provisional`).
class ProvisionalVault extends Notifier<LocalOnlyVault?> {
  @override
  LocalOnlyVault? build() {
    ref.onDispose(() {
      final open = _open;
      _open = null;
      if (open != null) unawaited(open.close().catchError((Object _) {}));
    });
    return null;
  }

  /// The vault open now ([state], readable while disposing).
  LocalOnlyVault? _open;
  var _stopped = false;
  Future<LocalOnlyVault>? _opening;

  void _set(LocalOnlyVault? vault) {
    _open = vault;
    if (ref.mounted) state = vault;
  }

  /// Whether a promotion has stopped it (nothing opens it again until [resume]).
  bool get stopped => _stopped;

  /// The vault [localId], opened once; throws while [stopped].
  Future<LocalOnlyVault> open(String localId) {
    if (_stopped) return Future.error(StateError('The provisional vault is being promoted'));
    final open = _open;
    if (open != null && open.localId == localId && !open.isClosed) return Future.value(open);
    return _opening ??= () async {
      try {
        if (open != null) await open.close();
        final vault = await ref.read(provisionalOpenerProvider)(localId);
        if (_stopped || !ref.mounted) {
          await vault.close();
          throw StateError('The provisional vault is being promoted');
        }
        _set(vault);
        return vault;
      } finally {
        _opening = null;
      }
    }();
  }

  /// Closes it and keeps it closed: the promotion's carry reads it next.
  Future<void> stop() async {
    _stopped = true;
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } on Object {
        // It failed, or was refused for being stopped: nothing is open.
      }
    }
    await close();
  }

  /// The promotion is over (it did not adopt): [open] works again.
  void resume() => _stopped = false;

  /// Closes it (the promotion adopted it, or the session moved on).
  Future<void> close() async {
    final open = _open;
    _set(null);
    await open?.close();
  }
}

final provisionalVaultProvider = NotifierProvider<ProvisionalVault, LocalOnlyVault?>(
  ProvisionalVault.new,
);
