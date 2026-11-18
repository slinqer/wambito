// TEMPORARY probe (branch fix/sqlite-lock-ci only): how long a waiter waits for the write lock,
// per journal mode, isolate and busy_timeout, while another connection holds it for 1.5 s.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _open(String path, String mode, int timeout) =>
    databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA busy_timeout = $timeout');
          await db.rawQuery('PRAGMA journal_mode = $mode');
        },
      ),
    );

Future<String> _wait(String path, String mode, int timeout) async {
  final db = await _open(path, mode, timeout);
  final sw = Stopwatch()..start();
  String r;
  try {
    await db.execute('BEGIN IMMEDIATE');
    r = 'got it after ${sw.elapsedMilliseconds}ms';
    await db.execute('COMMIT');
  } catch (e) {
    r = 'FAILED after ${sw.elapsedMilliseconds}ms';
  }
  await db.close();
  return r;
}

void main() {
  sqfliteFfiInit();
  test('matrix probe', () async {
    final lines = <String>[];
    for (final mode in ['wal', 'delete']) {
      for (final where in ['other-isolate']) {
        for (final timeout in [300, 5000, 20000]) {
          final dir = Directory.systemTemp.createTempSync('matrix');
          final path = '${dir.path}/m.db';
          final holder = await _open(path, mode, timeout);
          await holder.execute('CREATE TABLE t(x)');
          await holder.execute('BEGIN IMMEDIATE');
          await holder.execute('INSERT INTO t VALUES (1)');
          final Future<String> waiter = where == 'same-isolate'
              ? _wait(path, mode, timeout)
              : Isolate.run(() {
                  sqfliteFfiInit();
                  return _wait(path, mode, timeout);
                });
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          await holder.execute('COMMIT');
          lines.add('$mode $where timeout=$timeout: ${await waiter}');
          await holder.close();
          dir.deleteSync(recursive: true);
        }
      }
    }
    // ignore: avoid_print
    print('MATRIX\n${lines.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
