import 'dart:async';

import 'package:dio/dio.dart';

import '../local/backend.dart';
import '../local/keys.dart';
import '../local/sqlite_store.dart';
import '../local/sync.dart';
import '../local/vault_lock.dart';
import '../vault/encryption_mode.dart' show EncryptionMode, VaultAccount;
import 'queued_capture.dart';

/// How a headless run ended; `wambito/background` `finished` sends [BackgroundOutcome.name].
enum BackgroundOutcome {
  /// Nothing changed in the vault.
  done,

  /// Captures or confirms were saved, or the sync brought changes: the app (if alive) refreshes.
  changed,

  /// No session, or the sync was refused with a 401.
  signedOut,

  /// The account is not a `preview` one: nothing here is for this engine.
  notPreview,

  /// This phone holds no keys for the account.
  locked,

  /// Another engine holds the vault's lease: nothing was touched.
  busy,

  /// Anything else; the queue is left as it was (D23).
  failed,
}

/// What a run needs from the outside, so a test can fake each part (D14 for the real ones).
class BackgroundDeps {
  const BackgroundDeps({
    required this.token,
    required this.recall,
    required this.loadKeys,
    required this.openStore,
    required this.network,
    required this.lease,
    required this.now,
    this.refreshKeys,
    this.dropKeyVersion,
    this.deadline,
  });

  /// The session's token, or null when signed out.
  final Future<String?> Function() token;

  /// What the phone kept of the account for that session (`EncryptionStore.recall`).
  final Future<VaultAccount?> Function(String token) recall;
  final Future<LocalKeys?> Function(String userId) loadKeys;

  /// Opens the vault on its own connection (`SqliteStore.open(userId, background: true)`).
  final Future<SqliteStore> Function(String userId) openStore;

  /// The network for `/v2` (base `<server>/api`), with the background headers of D14.
  final Dio Function(String token) network;

  /// The vault's lease, or null when another engine holds it.
  final Future<VaultLease?> Function(String userId) lease;
  final DateTime Function() now;

  /// `keys.dart` `refreshKeys` for the account, for a newer key version the sync meets. Without it
  /// the run keeps the keys it loaded.
  final Future<Keyring> Function(String userId, Dio network)? refreshKeys;
  final Future<void> Function(String userId, int keyV)? dropKeyVersion;

  /// When the run must stop, well before native code's budget ends the engine (which would leave the
  /// lease for its whole ttl): past it the engine stops at its next fence, the effects are skipped,
  /// and the run acks what it saved and releases the lease. Null: no deadline.
  final DateTime? deadline;
}

/// Cancels every request of [dio] still running at [deadline] and refuses any made after it, so a
/// slow network cannot keep a run past its deadline (the sync reads it as `offline` and stops).
void cutAtDeadline(Dio dio, DateTime deadline) {
  final cancel = CancelToken();
  final left = deadline.difference(DateTime.now());
  if (left <= Duration.zero) {
    cancel.cancel('deadline');
  } else {
    Timer(left, () => cancel.cancel('deadline'));
  }
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.cancelToken = cancel;
        if (cancel.isCancelled) {
          return handler.reject(
            DioException.requestCancelled(requestOptions: options, reason: 'deadline'),
          );
        }
        handler.next(options);
      },
    ),
  );
}

/// What a run writes outside the vault once it has synced, for the account it ran for: the home
/// widget's snapshot and the due-notice list (D10, D11, D12).
class BackgroundEffects {
  const BackgroundEffects({required this.widget, required this.due});

  final Future<void> Function(String userId, LocalBackend backend) widget;
  final Future<void> Function(String userId, LocalBackend backend) due;
}

class BackgroundReport {
  const BackgroundReport(this.outcome, [this.captured = const []]);

  final BackgroundOutcome outcome;

  /// The local `POST /v1/captures` answers (201 created, 200 merged), for the notifications.
  final List<Map<String, Object?>> captured;
}

/// A lease the run already holds, lent to the engine: renewing is the real lease's, releasing is the
/// run's alone (the engine releases after its pass, and the run still needs the lease for its
/// effects). Past the run's deadline it no longer renews, so the engine stops at its next fence.
class _Borrowed implements VaultLease {
  _Borrowed(this._lease, this._past);

  final VaultLease _lease;
  final bool Function() _past;

  @override
  Future<bool> renew() async => !_past() && await _lease.renew();

  @override
  Future<void> release() async {}
}

const _ended = {
  SyncProblemCode.unauthorized,
  SyncProblemCode.sessionChanged,
  SyncProblemCode.deviceRemoved,
};

/// One background run. Order: token, the account (must be `preview`), keys, lease, store
/// (`background: true`), the captures and the confirms through the local backend, one sync (with the
/// lease the run holds), the effects, then [ack] of what was saved, then the store closes and the
/// lease goes (always).
///
/// - Each capture is sent with its own `key` as the `Idempotency-Key` (R3). Answer 201 (`created`) or
///   200 (`merged`, e.g. a retry after a crash) is a success: the capture is acked and its answer
///   goes to `captured`. Any other status leaves it unacked, in the queue.
/// - A confirm is `POST /v1/transactions/review` for its id; 200 and 404 (unknown: dropped) are acked.
/// - [ack] runs last: a crash anywhere before it leaves everything queued, and the next run merges
///   what was already saved (Review Focus 1). Never called when the lease was not taken (`busy`),
///   on `locked`, `signedOut`, `notPreview`, or when saving or the sync threw. The effects are best
///   effort: one that throws is skipped, never the ack.
/// - Past [BackgroundDeps.deadline] the sync stops at its next fence and the effects are skipped;
///   what was saved is still acked, and the lease released.
Future<BackgroundReport> runBackground(
  BackgroundDeps deps,
  BackgroundEffects effects, {
  List<QueuedCapture> captures = const [],
  List<String> confirms = const [],
  Future<void> Function(List<String> keys, List<String> confirms)? ack,
}) async {
  final captured = <Map<String, Object?>>[];
  SqliteStore? store;
  VaultLease? lease;
  try {
    final token = await deps.token();
    if (token == null) return const BackgroundReport(BackgroundOutcome.signedOut);
    final account = await deps.recall(token);
    // Not known (another session's, never kept): never guess, and never let native code send in
    // clear; the queue waits for an app start to record it.
    if (account == null) return const BackgroundReport(BackgroundOutcome.failed);
    if (account.mode != EncryptionMode.preview) {
      return const BackgroundReport(BackgroundOutcome.notPreview);
    }
    final profile = account.profile;
    final userId = profile.id;
    final keys = await deps.loadKeys(userId);
    if (keys == null) return const BackgroundReport(BackgroundOutcome.locked);
    lease = await deps.lease(userId);
    if (lease == null) return const BackgroundReport(BackgroundOutcome.busy);

    final opened = store = await deps.openStore(userId);
    final backend = createLocalBackend(
      store: opened,
      now: deps.now,
      unavailable: localUnavailable,
      timezone: profile.timezone,
      profile: LocalProfile(
        id: userId,
        email: profile.email,
        isAnonymous: profile.isAnonymous,
        encryption: 'preview',
      ),
    );

    final savedKeys = <String>[];
    for (final capture in captures) {
      final res = await backend.handle(
        'POST',
        '/v1/captures',
        const {},
        capture.body,
        headers: {'idempotency-key': capture.key},
      );
      if (res != null && (res.status == 201 || res.status == 200) && res.body is Map) {
        savedKeys.add(capture.key);
        captured.add((res.body! as Map).cast<String, Object?>());
      }
    }
    final doneConfirms = <String>[];
    var confirmed = 0;
    for (final id in confirms) {
      final res = await backend.handle('POST', '/v1/transactions/review', const {}, {
        'ids': [id],
      });
      if (res == null) continue;
      if (res.status == 200) {
        doneConfirms.add(id);
        confirmed++;
      } else if (res.status == 404) {
        doneConfirms.add(id);
      }
    }

    final deadline = deps.deadline;
    bool past() => deadline != null && !deps.now().isBefore(deadline);
    final network = deps.network(token);
    final engine = createSyncEngine(
      SyncEngineOptions(
        store: opened,
        dio: network,
        userId: userId,
        keyring: keys.keyring,
        refreshKeys: () async {
          final refresh = deps.refreshKeys;
          return refresh == null ? keys.keyring : refresh(userId, network);
        },
        dropKeyVersion: deps.dropKeyVersion == null ? null : (v) => deps.dropKeyVersion!(userId, v),
        now: () => deps.now().millisecondsSinceEpoch,
        lease: () async => _Borrowed(lease!, past),
      ),
    );
    final result = await engine.run();
    final problem = result.problem ?? result.error;

    var outcome = BackgroundOutcome.done;
    if (savedKeys.isNotEmpty ||
        confirmed > 0 ||
        result.pulled > 0 ||
        result.merged > 0 ||
        result.serverDeleted.isNotEmpty ||
        result.resynced) {
      outcome = BackgroundOutcome.changed;
    }
    if (problem == SyncProblemCode.unauthorized) outcome = BackgroundOutcome.signedOut;
    // Stopped by its own deadline, a run that saved something still reports it (the app refreshes,
    // the captures are notified); one that saved nothing is retried like a busy one.
    final cut = past();
    if (problem == SyncProblemCode.busy && !(cut && outcome == BackgroundOutcome.changed)) {
      outcome = BackgroundOutcome.busy;
    }
    if (problem == SyncProblemCode.sessionChanged ||
        problem == SyncProblemCode.deviceRemoved ||
        problem == SyncProblemCode.keyUnverified) {
      outcome = BackgroundOutcome.failed;
    }

    // The widget and the due list are this account's only while its session stands, and are
    // skipped past the deadline (the next run or the app draws them). Each is best effort: one that
    // throws skips neither the other nor the ack of what was saved.
    if (!_ended.contains(problem) && !cut) {
      try {
        await effects.widget(userId, backend);
      } on Object {
        // The widget keeps its last snapshot.
      }
      try {
        await effects.due(userId, backend);
      } on Object {
        // The phone keeps its last due list.
      }
    }
    if (ack != null && (savedKeys.isNotEmpty || doneConfirms.isNotEmpty)) {
      await ack(savedKeys, doneConfirms);
    }
    return BackgroundReport(outcome, captured);
  } on Object {
    return BackgroundReport(BackgroundOutcome.failed, captured);
  } finally {
    try {
      await store?.close();
    } on Object {
      // The file is released when the process ends.
    }
    try {
      await lease?.release();
    } on Object {
      // The lease expires by itself.
    }
  }
}
