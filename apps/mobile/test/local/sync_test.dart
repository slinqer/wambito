// Port of apps/web/app/local/sync.test.ts against a fake `/v2/sync` (fake_sync.dart), plus the
// phone's own: concurrentTriggersRunOnce and the per-account lock.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/core/records.dart' show Json;
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/store.dart';
import 'package:wambito/local/sync.dart';

import 'fake_sync.dart';

const user = 'user_sync';
const a = '01930000-0000-7000-8000-00000000000a';
const b = '01930000-0000-7000-8000-00000000000b';
const c = '01930000-0000-7000-8000-00000000000c';
const _cat = RecordType.category;

late Directory _dir;
var _counter = 0;
RecordKeys? _keys;

Future<RecordKeys> getKeys() async => _keys ??= await deriveRecordKeys(generateDataKey());

Future<RecordKeys> fresh() async => deriveRecordKeys(generateDataKey());

Future<SqliteStore> openStore() =>
    SqliteStore.open('device-${++_counter}', directory: _dir.path, factory: databaseFactoryFfi);

Keyring ring(Map<int, RecordKeys> entries) =>
    Keyring(current: entries.keys.reduce((x, y) => x > y ? x : y), byVersion: entries);

/// `refreshKeys` as the session builds it over `keys.dart`: this device's wrap of the server's
/// newest version is added and made current (only a higher one); `device_removed` once it has no
/// wrap. [once] replaces the next call (it gets the real one).
class Refresher {
  Refresher(this.server, this.ring);

  final FakeSync server;
  Keyring ring;
  int calls = 0;
  Future<Keyring> Function(Future<Keyring> Function() real)? once;

  Future<Keyring> real() async {
    if (server.removed) throw const KeysError('device_removed');
    if (server.tampered) throw const KeysError('tampered');
    final newest = server.wraps.keys.fold(0, (m, v) => v > m ? v : m);
    final keys = server.wraps[newest];
    if (keys != null && newest > ring.current) {
      ring = Keyring(current: newest, byVersion: {...ring.byVersion, newest: keys});
    }
    return ring;
  }

  Future<Keyring> call() {
    calls += 1;
    final hook = once;
    once = null;
    return hook != null ? hook(real) : real();
  }
}

class Device {
  Device(this.store, this.engine, this.problems, this.refresher, this.dropped);

  final SqliteStore store;
  final SyncEngine engine;
  final List<SyncProblem> problems;
  final Refresher refresher;

  /// The key versions the engine dropped.
  final List<int> dropped;
}

Future<Device> device(
  FakeSync server, {
  RecordKeys? k,
  Keyring? keyring,
  SqliteStore? store,
  int Function()? now,
  Duration debounce = const Duration(milliseconds: 20),
  Duration interval = const Duration(seconds: 100),
}) async {
  final s = store ?? await openStore();
  final problems = <SyncProblem>[];
  final dropped = <int>[];
  final ringNow = keyring ?? Keyring(current: 1, byVersion: {1: k ?? await getKeys()});
  final refresher = Refresher(server, ringNow);
  final engine = createSyncEngine(
    SyncEngineOptions(
      store: s,
      dio: server.dio(),
      userId: user,
      keyring: ringNow,
      refreshKeys: refresher.call,
      dropKeyVersion: (v) async => dropped.add(v),
      onError: problems.add,
      now: now,
      debounce: debounce,
      interval: interval,
      watchResume: (_) => () {},
    ),
  );
  return Device(s, engine, problems, refresher, dropped);
}

Json category(String name, [String color = '#fff']) => {
  's': 1,
  'name': name,
  'kind': 'expense',
  'icon': 'x',
  'color': color,
  'sortOrder': 0,
  'archivedAt': null,
  'systemKey': null,
};

Future<List<String>> names(SqliteStore store) async =>
    (await store.list(_cat)).map((r) => '${r.id}:${r.body['name']}/${r.body['color']}').toList()
      ..sort();

Future<String> sealedAt(RecordKeys k, String id, Object? body, int keyV) async => toBase64Url(
  await sealRecord(k, RecordContext(userId: user, type: _cat, id: id, keyV: keyV), body),
);

Future<String> sealedBy(RecordKeys k, String id, Object? body) => sealedAt(k, id, body, 1);

/// Writes a category on the server as another device would, sealed at [keyV].
Future<void> serverWrite(FakeSync server, RecordKeys k, String id, String name, int keyV) async {
  server.rows[id] = {
    'id': id,
    'type': 'category',
    'version': ++server.counter,
    'deleted': false,
    'keyV': keyV,
    'encV': 1,
    'body': await sealedAt(k, id, category(name), keyV),
  };
}

Future<Json> openOnServer(FakeSync server, RecordKeys k, String id) async {
  final row = server.rows[id]!;
  return (await openRecord(
    k,
    RecordContext(userId: user, type: _cat, id: id, keyV: row['keyV']! as int),
    fromBase64Url(row['body']! as String),
  ) as Map).cast<String, Object?>();
}

FakeAnswer status(int code, [Object? body = const {'code': 'x'}]) => (code, body);

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

List<String> ids(int n) => [
  for (var i = 0; i < n; i++) '01930000-0000-7000-8000-${'$i'.padLeft(12, '0')}',
];

const _all = 1 << 40;

void main() {
  sqfliteFfiInit();
  setUpAll(() => _dir = Directory.systemTemp.createTempSync('wambito-sync-test'));
  tearDownAll(() => _dir.deleteSync(recursive: true));

  group('push and pull between two devices', () {
    test('round-trips creates, edits and deletes', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await one.store.put(_cat, a, category('Food'));
      await one.store.put(_cat, b, category('Rent'));
      final r1 = await one.engine.run();
      expect(r1.ok, isTrue);
      expect(r1.pushed, 2);
      expect(await one.store.readOutbox(10), isEmpty);
      expect((await one.store.rawRecord(_cat, a))!.version, greaterThan(0));

      await two.engine.run();
      expect(await names(two.store), ['$a:Food/#fff', '$b:Rent/#fff']);
      expect(await two.store.readOutbox(10), isEmpty);

      await two.store.put(_cat, a, category('Groceries'));
      await two.store.delete(_cat, b);
      await two.engine.run();
      await one.engine.run();
      expect(await names(one.store), ['$a:Groceries/#fff']);
    });

    test('never stores plaintext on the server', () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.put(_cat, a, category('Secret name'));
      await one.engine.run();
      final wire = server.rows[a];
      expect(jsonEncode(wire), isNot(contains('Secret')));
      final opened = await openOnServer(server, await getKeys(), a);
      expect(opened['name'], 'Secret name');
    });
  });

  group('conflicts', () {
    Future<(FakeSync, Device, Device)> setup() async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await one.store.put(_cat, a, category('Food', '#111'));
      await one.engine.run();
      await two.engine.run();
      return (server, one, two);
    }

    test('merges disjoint fields', () async {
      final (_, one, two) = await setup();
      await one.store.put(_cat, a, category('Groceries', '#111'));
      await two.store.put(_cat, a, category('Food', '#222'));
      await one.engine.run();
      final r = await two.engine.run();
      expect(r.merged, 1);
      expect(await names(two.store), ['$a:Groceries/#222']);
      await one.engine.run();
      expect(await names(one.store), ['$a:Groceries/#222']);
      expect(await two.store.readOutbox(10), isEmpty);
    });

    test('keeps the local value of a field both changed', () async {
      final (_, one, two) = await setup();
      await one.store.put(_cat, a, category('Mine'));
      await two.store.put(_cat, a, category('Theirs'));
      await one.engine.run();
      await two.engine.run();
      await one.engine.run();
      expect(await names(one.store), ['$a:Theirs/#fff']);
      expect(await names(two.store), await names(one.store));
    });

    test('takes the server copy without pushing when the content is identical', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await one.store.put(_cat, c, category('Same'));
      await two.store.put(_cat, c, category('Same'));
      await one.engine.run();
      final posts = server.posts;
      final r = await two.engine.run();
      expect(r.ok, isTrue);
      expect(server.posts, posts + 1); // only the conflicting push, no re-push
      expect(await two.store.readOutbox(10), isEmpty);
      expect(
        (await two.store.rawRecord(_cat, c))!.version,
        (await one.store.rawRecord(_cat, c))!.version,
      );
    });

    test("keeps the server's deletion and reports an unsent edit", () async {
      final (_, one, two) = await setup();
      await one.store.delete(_cat, a);
      await one.engine.run();
      await two.store.put(_cat, a, category('Edited'));
      final r = await two.engine.run();
      expect(r.serverDeleted, [a]);
      expect(two.problems.any((p) => p.code == SyncProblemCode.serverDeleted), isTrue);
      expect(await two.store.list(_cat), isEmpty);
      expect(await two.store.readOutbox(10), isEmpty);
    });

    test('a local delete beats a server edit', () async {
      final (server, one, two) = await setup();
      await one.store.put(_cat, a, category('Edited'));
      await one.engine.run();
      await two.store.delete(_cat, a);
      await two.engine.run();
      expect(server.rows[a]!['deleted'], isTrue);
      await one.engine.run();
      expect(await one.store.list(_cat), isEmpty);
    });

    test('drops a change the server answers not_found to', () async {
      final (server, one, _) = await setup();
      server.rows.remove(a);
      await one.store.put(_cat, a, category('Edited'));
      final r = await one.engine.run();
      expect(r.dropped, [a]);
      expect(await one.store.readOutbox(10), isEmpty);
    });
  });

  group('pull', () {
    test('pages and follows next', () async {
      final server = FakeSync()..pullLimit = 2;
      final one = await device(server);
      final two = await device(server);
      for (final id in [a, b, c]) {
        await one.store.put(_cat, id, category('n${id.substring(id.length - 1)}'));
      }
      await one.engine.run();
      await two.engine.run();
      expect(await two.store.list(_cat), hasLength(3));
      expect(await two.store.getMeta('latest'), 3);
    });

    test('pages a full download past a purge with base=0', () async {
      final server = FakeSync()..pullLimit = 1;
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      await one.store.put(_cat, b, category('b'));
      await one.store.put(_cat, c, category('c'));
      await one.engine.run();
      await one.store.delete(_cat, b);
      await one.engine.run();
      server.purge();
      final other = await device(server);
      final r = await other.engine.run();
      expect(r.ok, isTrue);
      expect((await other.store.list(_cat)).map((x) => x.id).toList()..sort(), [a, c]);
    });

    test('resyncs on 410 and re-applies pending local edits', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await one.store.put(_cat, a, category('a', '#111'));
      await one.store.put(_cat, b, category('b'));
      await one.engine.run();
      await two.engine.run();
      await one.store.delete(_cat, b);
      await one.engine.run();
      server.purge();
      // Two never saw the delete; it has a pending edit that cannot be pushed (offline).
      await two.store.put(_cat, a, category('a', '#999'));
      server.offline = true;
      expect((await two.engine.run()).ok, isFalse);
      server.offline = false;
      final r = await two.engine.run();
      expect(r.ok, isTrue);
      expect(await names(two.store), ['$a:a/#999']);
      expect(server.rows.containsKey(a), isTrue);
      expect((await one.engine.run()).ok, isTrue);
      expect(await names(one.store), ['$a:a/#999']);
    });

    test('keeps a pending edit set aside across a resync that follows a failed push', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await one.store.put(_cat, a, category('a', '#111'));
      await one.store.put(_cat, b, category('b'));
      await one.engine.run();
      await two.engine.run();
      await one.store.delete(_cat, b);
      await one.engine.run();
      server.purge();
      // The push answers 500 once, then everything is fine: the 410 pull still must not lose it.
      await two.store.put(_cat, a, category('a', '#999'));
      var failed = false;
      server.intercept = (req, real) async {
        if (req.method == 'POST' && !failed) {
          failed = true;
          return status(500, const <String, Object?>{});
        }
        return real();
      };
      expect((await two.engine.run()).error, SyncProblemCode.server);
      expect((await two.engine.run()).ok, isTrue);
      expect(await names(two.store), ['$a:a/#999']);
    });

    test('quarantines a body sealed with another key, and a body that fails validation', () async {
      final server = FakeSync();
      final other = await fresh();
      server.rows[a] = {
        'id': a,
        'type': 'category',
        'version': ++server.counter,
        'deleted': false,
        'keyV': 1,
        'encV': 1,
        'body': await sealedBy(other, a, category('x')),
      };
      server.rows[b] = {
        'id': b,
        'type': 'category',
        'version': ++server.counter,
        'deleted': false,
        'keyV': 1,
        'encV': 1,
        'body': await sealedBy(await getKeys(), b, {'nope': 1}),
      };
      final good = await device(server);
      await good.store.put(_cat, c, category('fine'));
      await good.engine.run();
      final r = await good.engine.run();
      expect(r.ok, isTrue);
      expect(await good.store.quarantineCount(), 2);
      expect((await good.store.list(_cat)).map((x) => x.id), [c]);
    });
  });

  group('runs', () {
    test('fails offline, keeps the outbox, and succeeds once online', () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      server.offline = true;
      final off = await one.engine.run();
      expect(off.ok, isFalse);
      expect(off.error, SyncProblemCode.offline);
      expect(await one.store.readOutbox(10), hasLength(1));
      server.offline = false;
      expect((await one.engine.run()).ok, isTrue);
      expect(await one.store.readOutbox(10), isEmpty);
      expect(server.rows, hasLength(1));
    });

    test('coalesces overlapping runs and picks up writes made during one', () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      final p1 = one.engine.run();
      final p2 = one.engine.run();
      expect(identical(p1, p2), isTrue);
      await one.store.put(_cat, b, category('b'));
      await p1;
      expect(server.rows, hasLength(2));
      expect(await one.store.readOutbox(10), isEmpty);
    });

    test('start() syncs after a local write, ignoring its own commits', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      final stop = one.engine.start();
      await wait(100);
      await one.store.put(_cat, a, category('a'));
      one.engine.afterLocalWrite(); // the local backend's interceptor calls it
      await wait(400);
      expect(server.rows.containsKey(a), isTrue);
      final posts = server.posts;
      await two.store.put(_cat, b, category('b'));
      await two.engine.run();
      await wait(300);
      // one's own commits scheduled nothing
      expect(server.posts, posts + 1);
      stop();
    });

    test('concurrentTriggersRunOnce: three runs at once push and pull once, plus at most one '
        'follow-up', () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      final runs = [one.engine.run(), one.engine.run(), one.engine.run()];
      expect(identical(runs[0], runs[1]) && identical(runs[1], runs[2]), isTrue);
      final results = await Future.wait(runs);
      expect(results.every((r) => r.ok), isTrue);
      expect(server.posts, 1);
      // the first pass's pull, and at most the one follow-up pass the extra calls asked for
      expect(server.gets, inInclusiveRange(1, 2));
      expect(server.rows, hasLength(1));
    });

    test('a local write during a run schedules exactly one more run once it ends', () async {
      final server = FakeSync();
      final one = await device(server);
      final hold = Completer<void>();
      var held = false;
      server.intercept = (req, real) async {
        if (req.method == 'GET' && !held) {
          held = true;
          await hold.future;
        }
        return real();
      };
      final stop = one.engine.start();
      await wait(20);
      expect(held, isTrue);
      // three writes while the run waits on its pull: one follow-up run, not three
      for (final id in [a, b, c]) {
        await one.store.put(_cat, id, category(id));
        one.engine.afterLocalWrite();
      }
      hold.complete();
      await wait(300);
      expect(server.rows, hasLength(3));
      expect(await one.store.readOutbox(10), isEmpty);
      expect(server.posts, 1);
      stop();
    });

    test('two engines of the same account never run at once', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await one.store.put(_cat, a, category('a'));
      await two.store.put(_cat, b, category('b'));
      var inFlight = 0;
      var most = 0;
      server.intercept = (req, real) async {
        inFlight += 1;
        most = most > inFlight ? most : inFlight;
        await wait(5);
        inFlight -= 1;
        return real();
      };
      final results = await Future.wait([one.engine.run(), two.engine.run()]);
      expect(results.every((r) => r.ok), isTrue);
      expect(most, 1);
      expect(server.rows, hasLength(2));
    });
  });

  group('runs never loop and park what keeps failing', () {
    test('parks a change whose conflict copy cannot be opened, and the run ends', () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      await one.engine.run();
      final other = await fresh();
      server.rows[a]!
        ..['version'] = ++server.counter
        ..['body'] = await sealedBy(other, a, category('x'));
      await one.store.put(_cat, a, category('mine'));
      final r = await one.engine.run();
      expect(r.ok, isTrue);
      expect(r.parked, [a]);
      expect(one.problems, contains(const SyncProblem(SyncProblemCode.parked, ids: [a])));
      final [entry] = await one.store.readOutbox(10);
      expect(entry.park!.attempts, 1);
      expect(entry.park!.lastError, 'conflict_unreadable');
      // Backing off: the next run does not send it again.
      final posts = server.posts;
      await one.engine.run();
      expect(server.posts, posts);
    });

    test('parks a change the server gave no result for', () async {
      final server = FakeSync();
      final one = await device(server);
      server.intercept = (req, real) async {
        final res = await real();
        if (req.method != 'POST') return res;
        final results = ((res.$2! as Map)['results']! as List)
            .where((x) => (x as Map)['id'] != b)
            .toList();
        return status(200, {'results': results});
      };
      await one.store.put(_cat, a, category('a'));
      await one.store.put(_cat, b, category('b'));
      final r = await one.engine.run();
      expect(r.ok, isTrue);
      expect(r.parked, [b]);
      expect((await one.store.readOutbox(10)).map((e) => [e.id, e.park?.lastError]), [
        [b, 'no_result'],
      ]);
    });

    test('parks a change that conflicts on every push', () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      await one.engine.run();
      await one.store.put(_cat, a, category('b'));
      server.intercept = (req, real) async {
        if (req.method == 'POST') {
          // someone else always wins the race
          server.rows[a]?['version'] = ++server.counter;
        }
        return real();
      };
      final r = await one.engine.run();
      expect(r.ok, isTrue);
      expect(r.parked, [a]);
      expect((await one.store.readOutbox(10)).first.park!.lastError, 'conflict_limit');
    });

    test(
      'tries a parked change again after its back-off, or as soon as the person edits it',
      () async {
        final server = FakeSync();
        var clock = 1000000;
        final one = await device(server, now: () => clock);
        var reject = true;
        server.intercept = (req, real) async =>
            req.method == 'POST' && reject ? status(422) : real();
        await one.store.put(_cat, a, category('a'));
        expect((await one.engine.run()).parked, [a]);
        reject = false;
        expect((await one.engine.run()).pushed, 0);
        clock += 24 * 60 * 60 * 1000;
        expect((await one.engine.run()).pushed, 1);
        reject = true;
        await one.store.put(_cat, a, category('a2'));
        await one.engine.run();
        reject = false;
        await one.store.put(_cat, a, category('a3'));
        expect((await one.engine.run()).pushed, 1);
        expect(await one.store.readOutbox(10), isEmpty);
      },
    );

    test('backs off from 1 minute, doubling', () async {
      final server = FakeSync();
      var clock = 1000000;
      final one = await device(server, now: () => clock);
      server.intercept = (req, real) async => req.method == 'POST' ? status(422) : real();
      await one.store.put(_cat, a, category('a'));
      final untils = <int>[];
      for (var i = 0; i < 4; i++) {
        await one.engine.run();
        final park = (await one.store.readOutbox(10)).first.park!;
        untils.add(park.until - clock);
        clock = park.until;
      }
      expect(untils, [60000, 120000, 240000, 480000]);
    });
  });

  group('one bad change does not block the others', () {
    test('bisects a batch the server rejects whole and parks only the bad change', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await two.store.put(_cat, c, category('from two'));
      await two.engine.run();
      server.intercept = (req, real) async =>
          req.method == 'POST' && req.changeIds.contains(b) ? status(422) : real();
      await one.store.put(_cat, a, category('a'));
      await one.store.put(_cat, b, category('b'));
      final r = await one.engine.run();
      expect(r.ok, isTrue);
      expect(r.pushed, 1);
      expect(r.parked, [b]);
      expect(server.rows.containsKey(a), isTrue);
      final first = (await one.store.readOutbox(10)).first;
      expect(first.id, b);
      expect(first.park!.lastError, 'rejected_422');
      // The pull still ran.
      expect((await one.store.get(_cat, c))!.body['name'], 'from two');
    });

    test('parks the batch on 409 key_version_mismatch and still pulls', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await two.store.put(_cat, c, category('from two'));
      await two.engine.run();
      server.intercept = (req, real) async =>
          req.method == 'POST' ? status(409, {'code': 'key_version_mismatch'}) : real();
      await one.store.put(_cat, a, category('a'));
      final r = await one.engine.run();
      expect(r.ok, isTrue);
      expect(r.parked, [a]);
      expect((await one.store.readOutbox(10)).first.park!.lastError, 'rejected_409');
      expect((await one.store.get(_cat, c))!.body['name'], 'from two');
    });

    test('still stops on a server error, keeping the change unparked', () async {
      final server = FakeSync();
      final one = await device(server);
      server.intercept = (req, real) async => req.method == 'POST' ? status(503) : real();
      await one.store.put(_cat, a, category('a'));
      final r = await one.engine.run();
      expect(r.ok, isFalse);
      expect(r.error, SyncProblemCode.server);
      expect((await one.store.readOutbox(10)).first.park, isNull);
    });
  });

  group('pulls never overwrite or lose local edits', () {
    test(
      'does not apply a pulled record over a local write made while the page was opened',
      () async {
        // The web wraps the store's `transaction` to write between the decrypt and the apply. The
        // phone's store cannot be wrapped, so the write goes into that same window through the key
        // refresh the pulled record (under a newer keyV) needs.
        final server = FakeSync();
        final k1 = await fresh();
        final k2 = await fresh();
        final twoStore = await openStore();
        await twoStore.put(
          _cat,
          a,
          category('a'),
          const WriteOptions(origin: 'remote', version: 1, keyV: 1),
        );
        await twoStore.setMeta('latest', 1);
        server.counter = 1;
        await serverWrite(server, k2, a, 'server edit', 2);
        var injected = false;
        final engine = createSyncEngine(
          SyncEngineOptions(
            store: twoStore,
            dio: server.dio(),
            userId: user,
            keyring: ring({1: k1}),
            refreshKeys: () async {
              if (!injected) {
                injected = true;
                await twoStore.put(_cat, a, category('typed meanwhile'));
              }
              return ring({1: k1, 2: k2});
            },
          ),
        );
        // Only the pull: the push of the injected write comes in a later run.
        server.intercept = (req, real) async =>
            req.method == 'POST' ? throw const Offline() : real();
        await engine.run();
        expect(injected, isTrue);
        expect((await twoStore.get(_cat, a))!.body['name'], 'typed meanwhile');
        expect((await twoStore.readOutbox(10)).map((e) => e.id), [a]);
      },
    );

    test("takes the server's copy of a deterministic id both devices created (paid beats "
        'pending)', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      Json occurrence(String status) => {
        's': 1,
        'name': 'Rent',
        'amount': -80000,
        'currency': 'COP',
        'date': '2026-11-01',
        'status': status,
        'note': null,
        'categoryId': a,
        'accountId': null,
        'recurrenceId': b,
        'occurrenceMonth': '2026-11',
        'source': 'recurrence',
        'needsReview': false,
        'captureSource': null,
        'capturedAt': null,
        'captureMerchantKey': null,
      };
      await one.store.put(RecordType.transaction, c, occurrence('paid'));
      await one.engine.run();
      final version = server.rows[c]!['version'];
      await two.store.put(RecordType.transaction, c, occurrence('pending'));
      final posts = server.posts;
      final r = await two.engine.run();
      expect(r.ok, isTrue);
      expect(server.posts, posts + 1);
      expect(server.rows[c]!['version'], version);
      expect((await two.store.get(RecordType.transaction, c))!.body['status'], 'paid');
      expect(await two.store.readOutbox(10), isEmpty);
    });

    test('carries fields it does not know through a conflict merge', () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      await one.engine.run();
      // A newer client adds a field this one does not know.
      server.rows[a]!
        ..['version'] = ++server.counter
        ..['body'] = await sealedBy(await getKeys(), a, {
          ...category('a'),
          'future': {'x': 1},
        });
      await one.store.put(_cat, a, category('renamed'));
      await one.engine.run();
      final opened = await openOnServer(server, await getKeys(), a);
      expect(opened['name'], 'renamed');
      expect(opened['future'], {'x': 1});
    });
  });

  group('resync keeps pending edits', () {
    Future<(FakeSync, Device, Device)> stale() async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await one.store.put(_cat, a, category('a', '#111'));
      await one.store.put(_cat, b, category('b'));
      await one.engine.run();
      await two.engine.run();
      await one.store.delete(_cat, b);
      await one.store.put(_cat, a, category('renamed', '#111'));
      await one.store.put(_cat, c, category('c'));
      await one.engine.run();
      server.purge();
      return (server, one, two);
    }

    test('re-applies only the touched fields onto the fresh server copy', () async {
      final (server, _, two) = await stale();
      await two.store.put(_cat, a, category('a', '#999'));
      var rejected = false;
      server.intercept = (req, real) async {
        if (req.method == 'POST' && !rejected) {
          rejected = true;
          return status(422);
        }
        return real();
      };
      final r = await two.engine.run();
      expect(r.ok, isTrue);
      expect(r.resynced, isTrue);
      expect(await names(two.store), ['$a:renamed/#999', '$c:c/#fff']);
      await two.engine.run();
      expect(await two.store.readOutbox(10), isEmpty);
    });

    test('keeps the edit when the pull fails mid-resync, and recovers it on a later run', () async {
      final (server, one, two) = await stale();
      await two.store.put(_cat, a, category('a', '#999'));
      server.pullLimit = 1;
      var rejectPush = true;
      var breakPage = true;
      server.intercept = (req, real) async {
        if (req.method == 'POST' && rejectPush) {
          rejectPush = false;
          return status(422);
        }
        // The second page of the full download fails.
        final q = req.uri.queryParameters;
        if (req.method != 'POST' && q['base'] == '0' && q['since'] != '0' && breakPage) {
          breakPage = false;
          throw const Offline();
        }
        return real();
      };
      final failed = await two.engine.run();
      expect(failed.ok, isFalse);
      expect(failed.error, SyncProblemCode.offline);
      expect((await two.store.readOutbox(10)).map((e) => e.id), [a]);
      final r = await two.engine.run();
      expect(r.ok, isTrue);
      expect(await names(two.store), ['$a:renamed/#999', '$c:c/#fff']);
      expect(await two.store.readOutbox(10), isEmpty);
      await one.engine.run();
      expect(await names(one.store), ['$a:renamed/#999', '$c:c/#fff']);
    });
  });

  group('a closed vault', () {
    test('stops with `closed` when the vault was closed', () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.close();
      final r = await one.engine.run();
      expect(r.ok, isFalse);
      expect(r.error, SyncProblemCode.closed);
    });

    test('a run whose vault closes while it waits on the network writes nothing', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await two.store.put(_cat, a, category('a'));
      await two.engine.run();
      final hold = Completer<void>();
      server.intercept = (req, real) async {
        await hold.future;
        return real();
      };
      final running = one.engine.run();
      await wait(20);
      await one.store.close();
      hold.complete();
      final r = await running;
      expect(r.error, SyncProblemCode.closed);
      expect(one.problems, contains(const SyncProblem(SyncProblemCode.closed)));
    });
  });

  group('a change refused again and again is given up on', () {
    test('after 5 attempts it stops blocking pulls, and a later server edit shows up', () async {
      final server = FakeSync();
      var clock = 1000000;
      final one = await device(server, now: () => clock);
      final two = await device(server);
      final store = one.store;
      await store.put(_cat, a, category('Food'));
      await one.engine.run();
      await two.engine.run();

      // The server refuses one's edit of A, and only it.
      var refuse = true;
      server.intercept = (req, real) async =>
          refuse && req.method == 'POST' && req.changeIds.contains(a) ? status(422) : real();
      await store.put(_cat, a, category('Mine'));
      for (var i = 1; i <= 3; i++) {
        final r = await one.engine.run();
        expect(r.parked, [a]);
        expect(r.dropped, isEmpty);
        clock += 24 * 3600000;
      }
      // Still retrying (fourth attempt): the other device's edit does not overwrite it.
      refuse = false;
      await two.store.put(_cat, a, category('Two, first'));
      await two.engine.run();
      refuse = true;
      expect((await one.engine.run()).parked, [a]);
      expect((await store.get(_cat, a))!.body['name'], 'Mine');
      expect((await store.readOutbox(10)).first.abandoned, isFalse);
      clock += 24 * 3600000;
      // The fifth refusal gives up on it.
      expect((await one.engine.run()).dropped, [a]);
      expect((await store.readOutbox(10)).first.abandoned, isTrue);
      expect(one.problems, contains(const SyncProblem(SyncProblemCode.dropped, ids: [a])));

      // Never pushed again, and the next server edit comes in.
      clock += 24 * 3600000;
      final posts = server.posts;
      refuse = false;
      await two.store.put(_cat, a, category('Two, second'));
      await two.engine.run();
      final r = await one.engine.run();
      expect(r.ok, isTrue);
      expect(server.posts, posts + 1); // two's push only
      expect((await store.get(_cat, a))!.body['name'], 'Two, second');
      expect(await store.readOutbox(10), isEmpty);
    });

    test("a conflict that keeps losing takes the server's copy when it gives up", () async {
      final server = FakeSync();
      var clock = 1000000;
      final one = await device(server, now: () => clock);
      final store = one.store;
      await store.put(_cat, a, category('a'));
      await one.engine.run();
      await store.put(_cat, a, category('b'));
      server.intercept = (req, real) async {
        if (req.method == 'POST') server.rows[a]?['version'] = ++server.counter;
        return real();
      };
      SyncResult? last;
      for (var i = 1; i <= 5; i++) {
        last = await one.engine.run();
        clock += 24 * 3600000;
      }
      expect(last!.dropped, [a]);
      expect(await store.readOutbox(10), isEmpty);
      expect((await store.rawRecord(_cat, a))!.version, server.rows[a]!['version']);
      expect((await store.get(_cat, a))!.body['name'], 'a');
    });
  });

  group('the signed-in account', () {
    test("sends the vault's user id with every call", () async {
      final server = FakeSync();
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      await one.engine.run();
      expect(server.requests.length, greaterThanOrEqualTo(2));
      expect(server.requests.every((r) => r.user == user), isTrue);
    });

    test('stops on 409 session_changed, reports it and does not retry', () async {
      final server = FakeSync();
      var calls = 0;
      server.intercept = (req, real) async {
        calls += 1;
        return status(409, {'code': 'session_changed'});
      };
      final one = await device(server);
      await one.store.put(_cat, a, category('a'));
      final r = await one.engine.run();
      expect(r.ok, isFalse);
      expect(r.error, SyncProblemCode.sessionChanged);
      expect(
        one.problems,
        contains(const SyncProblem(SyncProblemCode.sessionChanged, status: 409)),
      );
      expect((await one.store.readOutbox(10)).first.park, isNull);
      // Its triggers stop too: no retry, no interval, no local write.
      final other = await device(
        server,
        debounce: const Duration(milliseconds: 5),
        interval: const Duration(milliseconds: 10),
      );
      calls = 0;
      final stop = other.engine.start();
      await wait(150);
      await other.store.put(_cat, b, category('b'));
      other.engine.afterLocalWrite();
      await wait(50);
      stop();
      expect(calls, 1);
    });
  });

  group('a create conflict racing a local write', () {
    test('keeps only the fields the person changed after the create', () async {
      final server = FakeSync();
      final one = await device(server);
      final two = await device(server);
      await two.store.put(_cat, c, category('Theirs', '#111'));
      await two.engine.run();
      await one.store.put(_cat, c, category('Mine', '#111'));
      var raced = false;
      server.intercept = (req, real) async {
        final res = await real();
        if (req.method == 'POST' && !raced) {
          raced = true;
          // The person changes the colour while the create is in flight.
          await one.store.put(_cat, c, category('Mine', '#999'));
        }
        return res;
      };
      await one.engine.run();
      expect(await names(one.store), ['$c:Theirs/#999']);
      await two.engine.run();
      expect(await names(two.store), ['$c:Theirs/#999']);
      expect(await one.store.readOutbox(10), isEmpty);
    });
  });

  group('key versions', () {
    test('a record under a newer keyV refreshes the keys, then applies', () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      server.wraps.addAll({1: k1, 2: k2});
      await serverWrite(server, k2, a, 'rotated', 2);
      await serverWrite(server, k2, b, 'rotated too', 2);
      final two = await device(server, k: k1);
      final r = await two.engine.run();
      expect(r.ok, isTrue);
      expect(r.pulled, 2);
      expect(r.quarantined, 0);
      expect(await two.store.quarantineCount(), 0);
      expect((await two.store.get(_cat, a))!.body['name'], 'rotated');
      expect((await two.store.rawRecord(_cat, a))!.keyV, 2);
      expect(two.refresher.calls, 1);
    });

    test('a record under a keyV no refresh can open goes to quarantine', () async {
      final server = FakeSync();
      final k1 = await fresh();
      server.wraps.addAll({1: k1, 2: await fresh()});
      await serverWrite(server, await fresh(), a, 'from the future', 3);
      await serverWrite(server, await fresh(), b, 'also', 3);
      final two = await device(server, k: k1);
      final r = await two.engine.run();
      expect(r.ok, isTrue);
      expect(r.quarantined, 2);
      expect(await two.store.quarantineCount(), 2);
      expect(await two.store.get(_cat, a), isNull);
      expect(two.refresher.calls, 1);
    });

    test(
      "a rotation that commits after the run's refresh does not quarantine the next keyV",
      () async {
        final server = FakeSync();
        final k1 = await fresh();
        final k2 = await fresh();
        final k3 = await fresh();
        server.wraps.addAll({1: k1, 2: k2});
        await serverWrite(server, k2, a, 'at two', 2);
        await serverWrite(server, k3, b, 'at three', 3);
        final two = await device(server, k: k1);
        two.refresher.once = (real) async {
          final ring = await real();
          server.wraps[3] = k3; // another device rotates right after this refresh
          return ring;
        };
        final r = await two.engine.run();
        expect(r.ok, isTrue);
        expect(r.pulled, 2);
        expect(r.quarantined, 0);
        expect((await two.store.get(_cat, b))!.body['name'], 'at three');
        expect(two.refresher.calls, 2);
      },
    );

    test(
      'a record quarantined under an unknown keyV opens once a later refresh reaches it',
      () async {
        final server = FakeSync();
        final k1 = await fresh();
        final k3 = await fresh();
        server.wraps[1] = k1;
        await serverWrite(server, k3, a, 'early', 3);
        final two = await device(server, k: k1);
        final first = await two.engine.run();
        expect(first.ok, isTrue);
        expect(first.quarantined, 1);
        expect(await two.store.quarantineCount(), 1);

        server.wraps[3] = k3;
        await serverWrite(server, k3, b, 'later', 3);
        final r = await two.engine.run();
        expect(r.ok, isTrue);
        expect((await two.store.get(_cat, a))!.body['name'], 'early');
        expect((await two.store.get(_cat, b))!.body['name'], 'later');
        expect(await two.store.quarantineCount(), 0);
      },
    );

    test('a quarantined record retries when useKeyring grows the keyring', () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      await serverWrite(server, k2, a, 'early', 2);
      final two = await device(server, k: k1);
      expect((await two.engine.run()).quarantined, 1);
      two.engine.useKeyring(ring({1: k1, 2: k2}));
      expect((await two.engine.run()).ok, isTrue);
      expect((await two.store.get(_cat, a))!.body['name'], 'early');
      expect(await two.store.quarantineCount(), 0);
    });

    test('a refresh that goes past the refused keyV re-seals and pushes, not parks', () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      final k3 = await fresh();
      server.wraps.addAll({1: k1, 2: k2});
      final one = await device(server, k: k1);
      one.refresher.once = (real) {
        server.wraps[3] = k3; // rotated again before this refresh read the wrap
        return real();
      };
      await one.store.put(_cat, a, category('typed before both'));
      final r = await one.engine.run();
      expect(r.ok, isTrue);
      expect(r.pushed, 1);
      expect(r.parked, isEmpty);
      expect(server.rows[a]!['keyV'], 3);
      expect((await openOnServer(server, k3, a))['name'], 'typed before both');
    });

    test('a push refused with key_version_mismatch refreshes, re-seals at the new keyV and pushes '
        'again', () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      server.wraps.addAll({1: k1, 2: k2});
      final one = await device(server, k: k1);
      await one.store.put(_cat, a, category('typed before the rotation'));
      final r = await one.engine.run();
      expect(r.ok, isTrue);
      expect(r.pushed, 1);
      expect(r.parked, isEmpty);
      expect(one.refresher.calls, 1);
      expect(server.rows[a]!['keyV'], 2);
      expect((await openOnServer(server, k2, a))['name'], 'typed before the rotation');
      expect(await one.store.readOutbox(10), isEmpty);
      expect((await one.store.rawRecord(_cat, a))!.keyV, 2);
    });

    test('a second key_version_mismatch in the run parks the change', () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      server.wraps.addAll({1: k1, 2: k2});
      final one = await device(server, k: k1);
      // the refresh never reaches version 2
      one.refresher.once = (_) async => ring({1: k1});
      await one.store.put(_cat, a, category('a'));
      final r = await one.engine.run();
      expect(r.parked, [a]);
      expect((await one.store.readOutbox(10)).first.park!.lastError, 'key_version_mismatch');
    });

    test('the upgrade pass re-seals old records and drops the old key when none is left', () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      final store = await openStore();
      final before = await device(server, k: k1, store: store);
      for (final id in [a, b, c]) {
        await store.put(_cat, id, category('n${id.substring(id.length - 1)}'));
      }
      await before.engine.run();
      expect(server.rows.values.map((r) => r['keyV']), [1, 1, 1]);
      // This phone now holds version 2 (a rotation); its records are still under 1.
      server.wraps.addAll({1: k1, 2: k2});
      final after = await device(server, store: store, keyring: ring({1: k1, 2: k2}));
      final versions = {
        for (final id in [a, b, c]) id: server.rows[id]!['version']! as int,
      };
      final r = await after.engine.run();
      expect(r.ok, isTrue);
      expect(server.rows.values.map((row) => row['keyV']), [2, 2, 2]);
      for (final id in [a, b, c]) {
        expect(server.rows[id]!['version']! as int, greaterThan(versions[id]!));
        expect((await openOnServer(server, k2, id))['name'], 'n${id.substring(id.length - 1)}');
        expect((await store.rawRecord(_cat, id))!.keyV, 2);
      }
      expect(await store.readOutbox(10), isEmpty);
      expect(after.dropped, [1]);
      // The next run has nothing left to re-seal.
      final posts = server.posts;
      await after.engine.run();
      expect(server.posts, posts);
    });

    test('the upgrade pass does at most 500 per run', () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      final store = await openStore();
      final before = await device(server, k: k1, store: store);
      final all = ids(501);
      await store.transaction((tx) async {
        for (final id in all) {
          await tx.put(_cat, id, category('x'));
        }
      });
      await before.engine.run();
      server.wraps.addAll({1: k1, 2: k2});
      final after = await device(server, store: store, keyring: ring({1: k1, 2: k2}));
      expect((await after.engine.run()).ok, isTrue);
      int at(int v) => server.rows.values.where((r) => r['keyV'] == v).length;
      expect(at(2), 500);
      expect(at(1), 1);
      expect(after.dropped, isEmpty);
      expect((await after.engine.run()).ok, isTrue);
      expect(at(2), 501);
      expect(after.dropped, [1]);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test("a conflict on a re-seal takes the server's copy", () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      final store = await openStore();
      final before = await device(server, k: k1, store: store);
      await store.put(_cat, a, category('old'));
      await before.engine.run();
      server.wraps.addAll({1: k1, 2: k2});
      final after = await device(server, store: store, keyring: ring({1: k1, 2: k2}));
      // Another device edits A (under the new key) between this phone's pull and its re-seal.
      var raced = false;
      server.intercept = (req, real) async {
        if (req.method == 'POST' && !raced && req.changeIds.contains(a)) {
          raced = true;
          await serverWrite(server, k2, a, 'theirs', 2);
        }
        return real();
      };
      final r = await after.engine.run();
      expect(r.ok, isTrue);
      expect(raced, isTrue);
      final version = server.rows[a]!['version'];
      expect((await openOnServer(server, k2, a))['name'], 'theirs');
      expect((await store.get(_cat, a))!.body['name'], 'theirs');
      final raw = (await store.rawRecord(_cat, a))!;
      expect(raw.version, version);
      expect(raw.keyV, 2);
      expect(await store.readOutbox(10), isEmpty);
    });

    test('device_removed stops the engine and reports it', () async {
      final server = FakeSync();
      final k1 = await fresh();
      server.wraps.addAll({1: k1, 2: await fresh()});
      server.removed = true;
      await serverWrite(server, await fresh(), a, 'after my removal', 2);
      final two = await device(server, k: k1);
      final r = await two.engine.run();
      expect(r.ok, isFalse);
      expect(r.error, SyncProblemCode.deviceRemoved);
      expect(r.problem, SyncProblemCode.deviceRemoved);
      expect(two.problems, contains(const SyncProblem(SyncProblemCode.deviceRemoved)));
      expect(await two.store.quarantineCount(), 0);
      // Its triggers stop: no retry, no interval, no local write.
      var calls = 0;
      server.intercept = (req, real) {
        calls += 1;
        return real();
      };
      final engine = createSyncEngine(
        SyncEngineOptions(
          store: two.store,
          dio: server.dio(),
          userId: user,
          keyring: ring({1: k1}),
          refreshKeys: Refresher(server, ring({1: k1})).call,
          debounce: const Duration(milliseconds: 5),
          interval: const Duration(milliseconds: 10),
          watchResume: (_) => () {},
        ),
      );
      final stop = engine.start();
      await wait(150);
      await two.store.put(_cat, b, category('b'));
      engine.afterLocalWrite();
      await wait(50);
      stop();
      expect(calls, 1);
    });

    test(
      'a tampered refresh stops the run with problem key_unverified and keeps the outbox',
      () async {
        final server = FakeSync();
        final k1 = await fresh();
        server.wraps.addAll({1: k1, 2: await fresh()});
        server.tampered = true;
        final two = await device(server, k: k1);
        await two.store.put(_cat, a, category('mine'));
        final r = await two.engine.run();
        expect(r.ok, isFalse);
        expect(r.error, SyncProblemCode.keyUnverified);
        expect(r.problem, SyncProblemCode.keyUnverified);
        expect(two.problems, contains(const SyncProblem(SyncProblemCode.keyUnverified)));
        expect(two.refresher.calls, 1);
        // nothing taken, nothing lost: the edit waits in the outbox, the vault stays open
        expect(server.rows, isEmpty);
        final outbox = await two.store.readOutbox(10);
        expect(outbox.map((e) => e.id), [a]);
        expect(outbox.first.park, isNull);
        expect(outbox.first.abandoned, isFalse);
        expect((await two.store.get(_cat, a))!.body['name'], 'mine');
        expect(two.store.isClosed, isFalse);
        // its triggers stop, as for a removed phone
        var calls = 0;
        server.intercept = (req, real) {
          calls += 1;
          return real();
        };
        final engine = createSyncEngine(
          SyncEngineOptions(
            store: two.store,
            dio: server.dio(),
            userId: user,
            keyring: ring({1: k1}),
            refreshKeys: Refresher(server, ring({1: k1})).call,
            debounce: const Duration(milliseconds: 5),
            interval: const Duration(milliseconds: 10),
            watchResume: (_) => () {},
          ),
        );
        final stop = engine.start();
        await wait(150);
        await two.store.put(_cat, b, category('b'));
        engine.afterLocalWrite();
        await wait(50);
        stop();
        expect(calls, 1);
        expect((await two.store.readOutbox(10)).map((e) => e.id).toList()..sort(), [a, b]);
      },
    );

    test('pending edits are sealed under the current keyV, never an old one', () async {
      final server = FakeSync();
      final k1 = await fresh();
      final k2 = await fresh();
      final store = await openStore();
      final before = await device(server, k: k1, store: store);
      await store.put(_cat, a, category('a'));
      await before.engine.run();
      server.wraps.addAll({1: k1, 2: k2});
      final after = await device(server, store: store, keyring: ring({1: k1, 2: k2}));
      final sent = <int>[];
      server.intercept = (req, real) {
        if (req.method == 'POST') {
          for (final ch in req.body!['changes']! as List) {
            sent.add((ch as Map)['keyV']! as int);
          }
        }
        return real();
      };
      await store.put(_cat, a, category('edited'));
      await store.put(_cat, b, category('new'));
      final r = await after.engine.run();
      expect(r.ok, isTrue);
      expect(r.pushed, 2);
      expect(sent, [2, 2]);
      expect(after.refresher.calls, 0);
      expect((await openOnServer(server, k2, a))['name'], 'edited');
      expect((await openOnServer(server, k2, b))['name'], 'new');
      expect(await store.readOutbox(_all), isEmpty);
    });
  });
}
