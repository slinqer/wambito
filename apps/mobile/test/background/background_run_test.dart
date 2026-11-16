// The background run (`runBackground`): queued captures saved into the encrypted vault, one sync,
// the widget and due-list effects, then the acknowledgement (D1, D8, D9, D14, D23, R3).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/background/background_run.dart';
import 'package:wambito/background/queued_capture.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/backend.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/vault_lock.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/local/vault_session.dart' show VaultProfile;

import '../local/fake_sync.dart';

late Directory _dir;
late FakeSync _server;
var _n = 0;

String _userId = 'user_1';

VaultAccount _account({EncryptionMode mode = EncryptionMode.preview}) => VaultAccount(
  owner: 'owner',
  mode: mode,
  profile: VaultProfile(
    id: _userId,
    email: 'ana@wambito.test',
    isAnonymous: false,
    locale: 'es',
    timezone: 'UTC',
  ),
);

Future<LocalKeys> _keys() async => LocalKeys(
  keyring: Keyring(current: 1, byVersion: {1: await deriveRecordKeys(generateDataKey())}),
);

/// A vault that already has its settings (the seed of a real one).
Future<SqliteStore> _openStore(String userId) async {
  final store = await SqliteStore.open(
    userId,
    directory: _dir.path,
    factory: databaseFactoryFfi,
    background: true,
  );
  if ((await store.list(RecordType.settings)).isEmpty) {
    final backend = createLocalBackend(
      store: store,
      now: () => _now,
      profile: LocalProfile(id: userId, encryption: 'preview'),
    );
    await backend.handle('PATCH', '/v1/me', const {}, {
      'currency': 'EUR',
      'locale': 'es',
      'timezone': 'UTC',
    });
  }
  return store;
}

final _now = DateTime.utc(2026, 11, 4, 16);

class _Calls {
  final opened = <String>[];
  final leases = <String>[];
  final released = <String>[];
  final widget = <String>[];
  final due = <String>[];
  final acks = <({List<String> keys, List<String> confirms})>[];
  final networkTokens = <String>[];
}

({BackgroundDeps deps, BackgroundEffects effects, _Calls calls, Lease lease}) _make({
  String? token = 'tok',
  VaultAccount? account,
  LocalKeys? keys,
  bool noKeys = false,
  bool noLease = false,
  Future<SqliteStore> Function(String userId)? openStore,
  Future<void> Function(String userId, LocalBackend backend)? widget,
  Future<void> Function(String userId, LocalBackend backend)? due,
  DateTime? deadline,
}) {
  final calls = _Calls();
  final lease = Lease();
  final deps = BackgroundDeps(
    token: () async => token,
    recall: (t) async => account ?? _account(),
    loadKeys: (id) async => noKeys ? null : (keys ?? await _keys()),
    openStore: (id) async {
      calls.opened.add(id);
      return (openStore ?? _openStore)(id);
    },
    network: (t) {
      calls.networkTokens.add(t);
      return _server.dio();
    },
    lease: (id) async {
      calls.leases.add(id);
      if (noLease) return null;
      return lease.take(calls.released);
    },
    now: () => _now,
    deadline: deadline,
  );
  final effects = BackgroundEffects(
    widget: (id, backend) async {
      calls.widget.add(id);
      await widget?.call(id, backend);
    },
    due: (id, backend) async {
      calls.due.add(id);
      await due?.call(id, backend);
    },
  );
  return (deps: deps, effects: effects, calls: calls, lease: lease);
}

/// A lease that records its release; renews while held.
class Lease {
  VaultLease take(List<String> released) => _Fake(released);
}

class _Fake implements VaultLease {
  _Fake(this._released);

  final List<String> _released;
  int renews = 0;

  @override
  Future<bool> renew() async {
    renews++;
    return true;
  }

  @override
  Future<void> release() async => _released.add('released');
}

QueuedCapture _capture(
  String key, {
  int amount = 1250,
  String merchant = 'Mercadona',
  String at = '2026-11-04T15:00:00.000Z',
}) => QueuedCapture(
  key: key,
  kind: 'expense',
  amount: amount,
  currency: 'EUR',
  merchant: merchant,
  capturedAt: at,
  source: 'revolut',
);

/// An adapter that answers after 30 s, unless the request is cancelled.
class _Slow implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final done = Completer<ResponseBody>();
    final timer = Timer(
      const Duration(seconds: 30),
      () => done.complete(ResponseBody.fromString('{}', 200)),
    );
    unawaited(
      cancelFuture?.then((_) {
        timer.cancel();
        if (!done.isCompleted) done.completeError(StateError('cancelled'));
      }),
    );
    return done.future;
  }

  @override
  void close({bool force = false}) {}
}

Future<int> _txCount() async {
  final store = await _openStore(_userId);
  try {
    return (await store.list(RecordType.transaction)).length;
  } finally {
    await store.close();
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('wambito-bg');
    _server = FakeSync();
    _userId = 'user_${++_n}';
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  test('saves each capture, then acks it', () async {
    final m = _make();
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [
        _capture('k1'),
        _capture('k2', amount: 300, merchant: 'Lidl'),
      ],
      ack: (keys, confirms) async => m.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(report.outcome, BackgroundOutcome.changed);
    expect(await _txCount(), 2);
    expect(m.calls.acks.length, 1);
    expect(m.calls.acks.single.keys, ['k1', 'k2']);
    expect(m.calls.acks.single.confirms, isEmpty);
    expect(report.captured.length, 2);
    expect(report.captured.map((c) => c['result']), ['created', 'created']);
    expect(m.calls.released, ['released']);
  });

  test('a capture sent again merges (200) and is acked and answered', () async {
    final first = _make();
    await runBackground(first.deps, first.effects, captures: [_capture('k1')]);
    final again = _make();
    final report = await runBackground(
      again.deps,
      again.effects,
      captures: [_capture('k1')],
      ack: (keys, confirms) async => again.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(await _txCount(), 1);
    expect(again.calls.acks.single.keys, ['k1']);
    expect(report.captured.single['result'], 'merged');
  });

  test('a capture the backend refuses is not acked and not reported', () async {
    final m = _make();
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [_capture('bad', amount: -5), _capture('k2')],
      ack: (keys, confirms) async => m.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(m.calls.acks.single.keys, ['k2']);
    expect(report.captured.length, 1);
    expect(await _txCount(), 1);
  });

  test('a store that fails to open acks nothing', () async {
    final m = _make(openStore: (_) async => throw StateError('disk full'));
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [_capture('k1')],
      ack: (keys, confirms) async => m.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(report.outcome, BackgroundOutcome.failed);
    expect(m.calls.acks, isEmpty);
    expect(m.calls.released, ['released']);
  });

  test('a widget effect that throws skips neither the due effect nor the ack', () async {
    final m = _make(widget: (_, _) async => throw StateError('widget'));
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [_capture('k1')],
      ack: (keys, confirms) async => m.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(report.outcome, BackgroundOutcome.changed);
    expect(m.calls.due, [_userId]);
    expect(m.calls.acks.single.keys, ['k1']);
    expect(await _txCount(), 1);
  });

  test('a due effect that throws still acks what was saved', () async {
    final m = _make(due: (_, _) async => throw StateError('due'));
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [_capture('k1')],
      ack: (keys, confirms) async => m.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(report.outcome, BackgroundOutcome.changed);
    expect(m.calls.widget, [_userId]);
    expect(m.calls.acks.single.keys, ['k1']);
  });

  test('an ack that throws acks nothing: the run failed', () async {
    final m = _make();
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [_capture('k1')],
      ack: (keys, confirms) async => throw StateError('ack'),
    );
    expect(report.outcome, BackgroundOutcome.failed);
    expect(await _txCount(), 1, reason: 'the save stands; the next run merges the duplicate');
  });

  test('a run past its deadline stops at the next fence, skips the effects, acks and releases '
      'the lease', () async {
    final m = _make(deadline: _now);
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [_capture('k1')],
      ack: (keys, confirms) async => m.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(_server.posts + _server.gets, 0, reason: 'stopped at the first fence');
    expect(m.calls.widget, isEmpty);
    expect(m.calls.due, isEmpty);
    expect(m.calls.acks.single.keys, ['k1']);
    expect(report.outcome, BackgroundOutcome.changed, reason: 'the capture was saved');
    expect(m.calls.released, ['released']);
  });

  test('a run past its deadline with nothing saved is busy (retried)', () async {
    final m = _make(deadline: _now.subtract(const Duration(seconds: 1)));
    final report = await runBackground(m.deps, m.effects);
    expect(report.outcome, BackgroundOutcome.busy);
    expect(_server.posts + _server.gets, 0);
    expect(m.calls.released, ['released']);
  });

  test('a run before its deadline syncs as usual', () async {
    final m = _make(deadline: _now.add(const Duration(seconds: 20)));
    await runBackground(m.deps, m.effects, captures: [_capture('k1')]);
    expect(_server.gets, 1);
    expect(m.calls.widget, [_userId]);
  });

  test('cutAtDeadline cancels a request still running at the deadline', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://wambito.test/api'))..httpClientAdapter = _Slow();
    cutAtDeadline(dio, DateTime.now().add(const Duration(milliseconds: 50)));
    final watch = Stopwatch()..start();
    await expectLater(
      dio.get<Object?>('/v2/sync'),
      throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('cutAtDeadline refuses a request made after the deadline', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://wambito.test/api'))..httpClientAdapter = _Slow();
    cutAtDeadline(dio, DateTime.now().subtract(const Duration(seconds: 1)));
    await expectLater(dio.get<Object?>('/v2/sync'), throwsA(isA<DioException>()));
  });

  test('not preview', () async {
    final m = _make(account: _account(mode: EncryptionMode.plain));
    final report = await runBackground(m.deps, m.effects, captures: [_capture('k1')]);
    expect(report.outcome, BackgroundOutcome.notPreview);
    expect(m.calls.opened, isEmpty);
    expect(m.calls.leases, isEmpty);
  });

  test('signed out', () async {
    final m = _make(token: null);
    final report = await runBackground(m.deps, m.effects);
    expect(report.outcome, BackgroundOutcome.signedOut);
    expect(m.calls.opened, isEmpty);
  });

  test('no keys', () async {
    final m = _make(noKeys: true);
    final report = await runBackground(m.deps, m.effects, captures: [_capture('k1')]);
    expect(report.outcome, BackgroundOutcome.locked);
    expect(m.calls.opened, isEmpty);
  });

  test('busy', () async {
    final m = _make(noLease: true);
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [_capture('k1')],
      ack: (keys, confirms) async => m.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(report.outcome, BackgroundOutcome.busy);
    expect(m.calls.opened, isEmpty);
    expect(m.calls.acks, isEmpty);
    expect(_server.posts + _server.gets, 0);
  });

  test('syncs once and writes the widget and due list for this account', () async {
    // The first run settles the new vault (its seeded settings go up and come back).
    final settle = _make();
    await runBackground(settle.deps, settle.effects);
    _server.requests.clear();
    final getsBefore = _server.gets;
    final m = _make();
    final report = await runBackground(m.deps, m.effects);
    expect(_server.gets - getsBefore, 1);
    expect(_server.requests.every((r) => r.user == _userId), isTrue);
    expect(m.calls.widget, [_userId]);
    expect(m.calls.due, [_userId]);
    expect(report.outcome, BackgroundOutcome.done);
    expect(m.calls.networkTokens, ['tok']);
  });

  test('the engine uses the lease the run holds and never takes a second', () async {
    final m = _make();
    await runBackground(m.deps, m.effects, captures: [_capture('k1')]);
    expect(m.calls.leases, [_userId], reason: 'one lease in all');
    expect(m.calls.released, ['released'], reason: 'released once, by the run');
    expect(_server.gets, 1, reason: 'the engine ran: it did not see itself busy');
  });

  test('offline still saves, writes the effects and acks', () async {
    _server.offline = true;
    final m = _make();
    final report = await runBackground(
      m.deps,
      m.effects,
      captures: [_capture('k1')],
      ack: (keys, confirms) async => m.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(report.outcome, BackgroundOutcome.changed);
    expect(m.calls.widget, [_userId]);
    expect(m.calls.acks.single.keys, ['k1']);
  });

  test('a confirm posts review locally; an unknown id is acked and dropped', () async {
    final m = _make();
    final saved = await runBackground(m.deps, m.effects, captures: [_capture('k1')]);
    final id = (saved.captured.single['transaction']! as Map)['id']! as String;
    final again = _make();
    final report = await runBackground(
      again.deps,
      again.effects,
      confirms: [id, '01930000-0000-7000-8000-0000000000ff'],
      ack: (keys, confirms) async => again.calls.acks.add((keys: keys, confirms: confirms)),
    );
    expect(again.calls.acks.single.confirms, [id, '01930000-0000-7000-8000-0000000000ff']);
    expect(again.calls.acks.single.keys, isEmpty);
    expect(report.outcome, BackgroundOutcome.changed);
    final store = await _openStore(_userId);
    final tx = (await store.list(RecordType.transaction)).single;
    await store.close();
    expect(tx.body['needsReview'], false);
  });
}
