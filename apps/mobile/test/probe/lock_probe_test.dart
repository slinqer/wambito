// TEMPORARY probe (branch fix/sqlite-lock-ci only): measures how long a write waits for the vault
// file's lock in the scenario of sqlite_two_connections_test, and how a failure happens.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/sqlite_store.dart';

Map<String, Object?> _cat(String n) => {
  's': 1, 'name': n, 'kind': 'expense', 'icon': 'x', 'color': '#fff', 'sortOrder': 0,
  'archivedAt': null, 'systemKey': null,
};

Future<List<String>> _writes(SqliteStore s, String tag, Stopwatch clock) async {
  final out = <String>[];
  for (var i = 0; i < 5; i++) {
    final start = clock.elapsedMilliseconds;
    final sw = Stopwatch()..start();
    try {
      await s.transaction((tx) async {
        final hex = tag.codeUnitAt(0).toRadixString(16).padLeft(2, '0');
        final id = '01930000-0000-7000-8000-${hex}00000000${i.toString().padLeft(2, '0')}';
        await tx.put(RecordType.category, id, _cat('$tag$i'));
      });
      if (sw.elapsedMilliseconds > 500) out.add('SLOW $tag$i at ${start}ms took ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      out.add('FAIL $tag$i at ${start}ms after ${sw.elapsedMilliseconds}ms: '
          '${e.toString().replaceAll('\n', ' ').substring(0, 120)}');
    }
  }
  return out;
}

void main() {
  sqfliteFfiInit();
  final rounds = int.parse(Platform.environment['PROBE_ROUNDS'] ?? '40');
  test('lock probe', () async {
    final notes = <String>[];
    for (var round = 0; round < rounds; round++) {
      final dir = Directory.systemTemp.createTempSync('probe');
      final path = dir.path;
      final clock = Stopwatch()..start();
      final app = await SqliteStore.open('ana', directory: path, factory: databaseFactoryFfi);
      final others = [
        for (final tag in ['b', 'c'])
          Isolate.run(() async {
            sqfliteFfiInit();
            final c = Stopwatch()..start();
            SqliteStore store;
            try {
              store = await SqliteStore.open('ana', directory: path, factory: databaseFactoryFfi, background: true);
            } catch (e) {
              return ['OPENFAIL $tag after ${c.elapsedMilliseconds}ms: ${e.toString().replaceAll('\n', ' ')}'];
            }
            final opened = c.elapsedMilliseconds;
            final r = await _writes(store, tag, c);
            await store.close();
            return [if (opened > 500) 'SLOWOPEN $tag ${opened}ms', ...r];
          }),
      ];
      final res = await Future.wait([_writes(app, 'a', clock), ...others]);
      for (final r in res) {
        notes.addAll(r.map((n) => 'round $round: $n'));
      }
      await app.close();
      dir.deleteSync(recursive: true);
    }
    // ignore: avoid_print
    print('PROBE rounds=$rounds notes=${notes.length}\n${notes.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
