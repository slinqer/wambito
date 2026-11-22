import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/sqlite_store.dart';

/// The app's vault connection and a headless run's connection in one process, on sqflite's real
/// native side (one map of connections and one pool of threads for every engine). On a phone, a run
/// whose engine was destroyed mid-transaction kept the vault locked until the app was killed: every
/// read failed, and home said "No pudimos actualizar".
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('vault-lock'));
  tearDown(() async => dir.delete(recursive: true));

  test('a background connection left in a transaction is closed and the app reads again', () async {
    final app = await SqliteStore.open('ana', directory: dir.path);
    final bg = await SqliteStore.open('ana', directory: dir.path, background: true);
    final inside = Completer<void>();
    // Its engine is gone: nothing will ever finish this transaction.
    final orphan = bg.transaction((tx) async {
      await tx.get(RecordType.category, 'x');
      inside.complete();
      await Completer<void>().future;
    });
    unawaited(orphan.then((_) {}, onError: (Object _) {}));
    await inside.future;

    expect(await app.list(RecordType.transaction), isEmpty);
    // And for good: the next read does not wait.
    final sw = Stopwatch()..start();
    expect(await app.list(RecordType.transaction), isEmpty);
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    await app.close();
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('the app waiting for the lock no longer stops the run that holds it', () async {
    final app = await SqliteStore.open('bob', directory: dir.path);
    final bg = await SqliteStore.open('bob', directory: dir.path, background: true);
    Future<void>? appRead;
    final perStatement = <int>[];
    await bg.transaction((tx) async {
      await tx.get(RecordType.category, 'first');
      appRead = app.list(RecordType.transaction).then((_) {}, onError: (Object _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        await tx.get(RecordType.category, 'y$i');
        perStatement.add(sw.elapsedMilliseconds);
      }
    });
    // With a 5 s busy_timeout the first statement waited for the app's whole wait.
    expect(perStatement.every((ms) => ms < 1000), isTrue, reason: '$perStatement ms');
    await appRead;
    await bg.close();
    await app.close();
  }, timeout: const Timeout(Duration(minutes: 1)));
}
