// TEMPORARY probe (branch fix/sqlite-lock-ci only): what each connection really has, and how long a
// waiter really waits, on the CI runner.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/local/db.dart';

Future<String> _info(Database db, String who) async {
  final t = (await db.rawQuery('PRAGMA busy_timeout')).first.values.first;
  final j = (await db.rawQuery('PRAGMA journal_mode')).first.values.first;
  final v = (await db.rawQuery('select sqlite_version()')).first.values.first;
  return '$who busy_timeout=$t journal=$j sqlite=$v';
}

void main() {
  sqfliteFfiInit();
  test('pragma probe', () async {
    final dir = Directory.systemTemp.createTempSync('pragma');
    final path = dir.path;
    final app = await openVault('ana', directory: path, factory: databaseFactoryFfi);
    final lines = <String>[await _info(app, 'app')];
    final opts = (await app.rawQuery('PRAGMA compile_options')).map((r) => r.values.first).join(',');
    lines.add('compile_options=$opts');
    // The app holds the write lock for 1.5 s; a background connection in another isolate asks for it.
    await app.execute('BEGIN IMMEDIATE');
    final waited = Isolate.run(() async {
      sqfliteFfiInit();
      final bg = await openVault('ana', directory: path, factory: databaseFactoryFfi, singleInstance: false);
      final info = await _info(bg, 'bg');
      final sw = Stopwatch()..start();
      String r;
      try {
        await bg.execute('BEGIN IMMEDIATE');
        r = 'bg got the lock after ${sw.elapsedMilliseconds}ms';
        await bg.execute('COMMIT');
      } catch (e) {
        r = 'bg FAILED after ${sw.elapsedMilliseconds}ms: ${e.toString().split('\n').first}';
      }
      await bg.close();
      return '$info\n$r';
    });
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await app.execute('COMMIT');
    lines.add(await waited);
    await app.close();
    // ignore: avoid_print
    print('PRAGMA\n${lines.join('\n')}');
  });
}
