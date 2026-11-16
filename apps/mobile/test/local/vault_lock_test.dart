// The cross-engine lease of the vault: a lock file made with an exclusive create, an expired one
// taken over by an atomic rename. The takers are separate isolates (as the app's and a headless
// engine are in one process); the file system arbitrates across processes the same way.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wambito/local/vault_lock.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wambito-lock'));
  tearDown(() => dir.deleteSync(recursive: true));

  File lockFile() => File(p.join(dir.path, vaultLockFileName('ana')));

  test('the lock file sits next to the vault file', () {
    expect(vaultLockFileName('ana'), 'wambito-vault-ana.db-lock');
  });

  test('two isolates race for one lease', () async {
    final path = dir.path;
    for (var round = 0; round < 5; round++) {
      final wins = await Future.wait([
        for (var i = 0; i < 6; i++)
          Isolate.run(() async {
            final lease = await tryLease('ana', holder: 'isolate-$i', directory: path);
            return lease != null;
          }),
      ]);
      expect(wins.where((w) => w).length, 1, reason: 'round $round: $wins');
      lockFile().deleteSync();
    }
  });

  test('an expired lease is taken over once', () async {
    final path = dir.path;
    for (var round = 0; round < 5; round++) {
      lockFile().writeAsStringSync(
        jsonEncode({
          'holder': 'gone',
          'token': 'old',
          'expiresAt': DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
        }),
      );
      final wins = await Future.wait([
        for (var i = 0; i < 6; i++)
          Isolate.run(() async {
            final lease = await tryLease('ana', holder: 'isolate-$i', directory: path);
            return lease != null;
          }),
      ]);
      expect(wins.where((w) => w).length, 1, reason: 'round $round: $wins');
      // The winner's lease is the live one now, and no taken-over file is left behind.
      expect(await tryLease('ana', holder: 'late', directory: path), isNull);
      expect(dir.listSync().map((f) => p.basename(f.path)), [vaultLockFileName('ana')]);
      lockFile().deleteSync();
    }
  });

  test('a stale claim of a dead taker is recovered by exactly one taker', () async {
    final path = dir.path;
    for (var round = 0; round < 5; round++) {
      final old = DateTime.now().subtract(const Duration(minutes: 1));
      lockFile().writeAsStringSync(
        jsonEncode({'holder': 'gone', 'token': 'T1', 'expiresAt': old.millisecondsSinceEpoch}),
      );
      final claim = File('${lockFile().path}.claim-T1')
        ..writeAsStringSync(
          jsonEncode({'holder': 'dead', 'token': 'C1', 'expiresAt': old.millisecondsSinceEpoch}),
        )
        ..setLastModifiedSync(old);
      expect(claim.existsSync(), isTrue);
      final wins = await Future.wait([
        for (var i = 0; i < 6; i++)
          Isolate.run(() async {
            final lease = await tryLease('ana', holder: 'isolate-$i', directory: path);
            return lease != null;
          }),
      ]);
      expect(wins.where((w) => w).length, 1, reason: 'round $round: $wins');
      expect(await tryLease('ana', holder: 'late', directory: path), isNull);
      expect(dir.listSync().map((f) => p.basename(f.path)), [vaultLockFileName('ana')]);
      lockFile().deleteSync();
    }
  });

  test('an empty claim of a dead taker is recovered by exactly one taker', () async {
    final path = dir.path;
    for (var round = 0; round < 5; round++) {
      final old = DateTime.now().subtract(const Duration(minutes: 1));
      lockFile().writeAsStringSync(
        jsonEncode({'holder': 'gone', 'token': 'T1', 'expiresAt': old.millisecondsSinceEpoch}),
      );
      File('${lockFile().path}.claim-T1')
        ..createSync()
        ..setLastModifiedSync(old);
      final wins = await Future.wait([
        for (var i = 0; i < 6; i++)
          Isolate.run(() async {
            final lease = await tryLease('ana', holder: 'isolate-$i', directory: path);
            return lease != null;
          }),
      ]);
      expect(wins.where((w) => w).length, 1, reason: 'round $round: $wins');
      expect(await tryLease('ana', holder: 'late', directory: path), isNull);
      expect(dir.listSync().map((f) => p.basename(f.path)), [vaultLockFileName('ana')]);
      lockFile().deleteSync();
    }
  });

  test('renew extends a live lease and fails once it was taken over or expired', () async {
    var clock = DateTime.utc(2026, 11, 16, 10);
    final lease = await tryLease('ana', holder: 'app', directory: dir.path, now: () => clock);
    clock = clock.add(const Duration(minutes: 9));
    expect(await lease!.renew(), isTrue);
    // 9 + 9 minutes: live only because of the renewal (ttl 10).
    clock = clock.add(const Duration(minutes: 9));
    expect(await tryLease('ana', holder: 'sync', directory: dir.path, now: () => clock), isNull);
    expect(await lease.renew(), isTrue);
    clock = clock.add(const Duration(minutes: 11));
    expect(await lease.renew(), isFalse);
    final taker = await tryLease('ana', holder: 'sync', directory: dir.path, now: () => clock);
    expect(taker, isNotNull);
    expect(await lease.renew(), isFalse);
    expect(await taker!.renew(), isTrue);
    expect(dir.listSync().map((f) => p.basename(f.path)), [vaultLockFileName('ana')]);
  });

  test('release deletes the file', () async {
    final lease = await tryLease('ana', holder: 'app', directory: dir.path);
    expect(lease, isNotNull);
    expect(lockFile().existsSync(), isTrue);
    await lease!.release();
    expect(lockFile().existsSync(), isFalse);
    expect(await tryLease('ana', holder: 'sync', directory: dir.path), isNotNull);
  });

  test('a live lease is not taken', () async {
    final first = await tryLease('ana', holder: 'app', directory: dir.path);
    expect(first, isNotNull);
    expect(await tryLease('ana', holder: 'sync', directory: dir.path), isNull);
    expect(
      await waitLease('ana', holder: 'sync', wait: Duration.zero, directory: dir.path),
      isNull,
    );
  });

  test('a lease of another account does not block', () async {
    expect(await tryLease('ana', holder: 'app', directory: dir.path), isNotNull);
    expect(await tryLease('bea', holder: 'app', directory: dir.path), isNotNull);
  });

  test('a lease expires after its ttl', () async {
    var clock = DateTime.utc(2026, 11, 16, 10);
    final first = await tryLease(
      'ana',
      holder: 'app',
      directory: dir.path,
      ttl: const Duration(minutes: 10),
      now: () => clock,
    );
    expect(first, isNotNull);
    clock = clock.add(const Duration(minutes: 9));
    expect(await tryLease('ana', holder: 'sync', directory: dir.path, now: () => clock), isNull);
    clock = clock.add(const Duration(minutes: 2));
    expect(await tryLease('ana', holder: 'sync', directory: dir.path, now: () => clock), isNotNull);
  });

  test('a released lease that was taken over does not delete the taker\'s file', () async {
    var clock = DateTime.utc(2026, 11, 16, 10);
    final slow = await tryLease('ana', holder: 'slow', directory: dir.path, now: () => clock);
    clock = clock.add(const Duration(minutes: 11));
    final taker = await tryLease('ana', holder: 'taker', directory: dir.path, now: () => clock);
    expect(taker, isNotNull);
    await slow!.release();
    expect(lockFile().existsSync(), isTrue);
  });

  test('waitLease gets the lease once it is released', () async {
    final first = await tryLease('ana', holder: 'app', directory: dir.path);
    Future<void>.delayed(const Duration(milliseconds: 300), first!.release);
    final got = await waitLease(
      'ana',
      holder: 'sync',
      wait: const Duration(seconds: 5),
      directory: dir.path,
    );
    expect(got, isNotNull);
  });

  test('a lock file left empty by a crash is taken over after the grace', () async {
    lockFile().createSync();
    final old = DateTime.now().subtract(const Duration(minutes: 1));
    lockFile().setLastModifiedSync(old);
    expect(await tryLease('ana', holder: 'sync', directory: dir.path), isNotNull);
  });

  test('a lock file just created and still empty is held', () async {
    lockFile().createSync();
    expect(await tryLease('ana', holder: 'sync', directory: dir.path), isNull);
  });
}
