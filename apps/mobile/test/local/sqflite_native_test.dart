import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wambito/local/db.dart' show vaultFileName;
import 'package:wambito/local/sqflite_native.dart';
import 'package:wambito/local/vault_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/sqflite');
  final calls = <MethodCall>[];
  late Directory dir;
  Map<String, Object?> databases = {};

  setUp(() {
    calls.clear();
    dir = Directory.systemTemp.createTempSync('wambito-sqflite');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        if (call.method == 'debug') return {'databases': databases};
        return null;
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    dir.deleteSync(recursive: true);
  });

  group('closeOrphanVaultConnections', () {
    String vault(String id) => p.join(dir.path, vaultFileName(id));

    test('closes only the background connections of that vault', () async {
      databases = {
        '1': {'path': vault('ana'), 'singleInstance': false},
        '2': {'path': vault('ana'), 'singleInstance': true},
        '3': {'path': vault('bob'), 'singleInstance': false},
      };
      final closed = await closeOrphanVaultConnections(
        'ana',
        directory: dir.path,
        channel: channel,
      );
      expect(closed, 1);
      final sent = calls.where((c) => c.method != 'debug').toList();
      // The open transaction keeps Android's connection checked out: closing alone never frees it.
      // sqflite runs a forced statement (-1) even inside another caller's transaction.
      expect(sent.map((c) => c.method), ['execute', 'closeDatabase']);
      expect(sent[0].arguments, {
        'id': 1,
        'sql': 'ROLLBACK',
        'arguments': <Object?>[],
        'inTransaction': false,
        'transactionId': -1,
      });
      expect(sent[1].arguments, {'id': 1});
    });

    test('closes the connection even when it had no transaction to roll back', () async {
      databases = {
        '4': {'path': vault('ana'), 'singleInstance': false},
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          if (call.method == 'debug') return {'databases': databases};
          if (call.method == 'execute') {
            throw PlatformException(code: 'sqlite_error', message: 'no transaction is active');
          }
          return null;
        },
      );
      expect(await closeOrphanVaultConnections('ana', directory: dir.path, channel: channel), 1);
      expect(calls.last.method, 'closeDatabase');
    });

    test('holds the lease while it closes, and releases it', () async {
      databases = {
        '7': {'path': vault('ana'), 'singleInstance': false},
      };
      VaultLease? during;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          if (call.method == 'debug') return {'databases': databases};
          during = await tryLease('ana', holder: 'background', directory: dir.path);
          return null;
        },
      );
      await closeOrphanVaultConnections('ana', directory: dir.path, channel: channel);
      expect(during, isNull, reason: 'no headless run may start while its connection is closed');
      final after = await tryLease('ana', holder: 'background', directory: dir.path);
      expect(after, isNotNull);
      await after!.release();
    });

    test('leaves everything open while a live run holds the lease', () async {
      databases = {
        '1': {'path': vault('ana'), 'singleInstance': false},
      };
      final live = await tryLease('ana', holder: 'background', directory: dir.path);
      final closed = await closeOrphanVaultConnections(
        'ana',
        directory: dir.path,
        channel: channel,
      );
      expect(closed, 0);
      expect(calls, isEmpty);
      await live!.release();
    });

    test('a plugin that cannot list its connections closes nothing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'x'),
      );
      expect(await closeOrphanVaultConnections('ana', directory: dir.path, channel: channel), 0);
    });
  });
}
