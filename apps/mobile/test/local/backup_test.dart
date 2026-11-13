import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/crypto/records.dart';
import 'package:wambito/local/backup.dart';
import 'package:wambito/local/sqlite_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('wambito/device');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('excludeVaultFromBackup sends the path on the device channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    await excludeVaultFromBackup('/data/vault');
    expect(calls.map((c) => c.method), ['excludeFromBackup']);
    expect(calls.single.arguments, {'path': '/data/vault'});
  });

  test('a phone without the method (a test host, a desktop) is not an error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw MissingPluginException());
    await excludeVaultFromBackup('/data/vault');
  });

  test(
    'opening the vault asks once for the exclusion, with the folder holding its files',
    () async {
      final dir = Directory.systemTemp.createTempSync('wambito-backup-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final paths = <String>[];
      final store = await SqliteStore.open(
        'user-1',
        directory: dir.path,
        factory: databaseFactoryFfi,
        excludeFromBackup: (path) async => paths.add(path),
      );
      await store.put(RecordType.category, 'a', {'name': 'A'});
      await store.close();
      expect(paths, [dir.path]);
    },
  );
}
