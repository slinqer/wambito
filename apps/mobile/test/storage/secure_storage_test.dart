import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/storage/secure_storage.dart';

/// A storage in memory that remembers what was read and written, and can fail a read.
class RecordingStorage extends FlutterSecureStorage {
  RecordingStorage(this.values, {this.failingRead});

  final Map<String, String> values;
  final String? failingRead;
  final List<String> reads = [];
  final List<String> writes = [];
  final List<String> deletes = [];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads.add(key);
    if (key == failingRead) throw PlatformException(code: 'keychain');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes.add(key);
    values[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletes.add(key);
    values.remove(key);
  }
}

void main() {
  const keys = ['session.token', 'session.guest', 'setting.server'];

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('uses first unlock on iOS', () {
    expect(appSecureStorage.iOptions.params['accessibility'], 'first_unlock_this_device');
  });

  test('keeps the Android options as they were', () {
    expect(appSecureStorage.aOptions, AndroidOptions.defaultOptions);
  });

  group('migrateKeychainAccessibility', () {
    test('rewrites items stored with the old accessibility', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final storage = RecordingStorage({
        'session.token': 'abc',
        'session.guest': 'false',
        'setting.server': 'https://example.test',
      });

      await migrateKeychainAccessibility(storage, keys);

      expect(storage.writes.where(keys.contains), keys);
      expect(storage.values['session.token'], 'abc');
      expect(storage.values['setting.server'], 'https://example.test');
      expect(storage.values[accessibilityFlagKey], 'first_unlock_this_device');
      expect(storage.deletes, isEmpty);

      storage.writes.clear();
      await migrateKeychainAccessibility(storage, keys);
      expect(storage.writes, isEmpty);
    });

    test('skips keys that hold nothing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final storage = RecordingStorage({'session.token': 'abc'});

      await migrateKeychainAccessibility(storage, keys);

      expect(storage.writes, ['session.token', accessibilityFlagKey]);
    });

    test('a failed read leaves the key alone and tries again next start', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final storage = RecordingStorage({
        'session.token': 'abc',
        'session.guest': 'false',
      }, failingRead: 'session.guest');

      await migrateKeychainAccessibility(storage, keys);

      expect(storage.values['session.guest'], 'false');
      expect(storage.values.containsKey(accessibilityFlagKey), isFalse);
      expect(storage.deletes, isEmpty);
    });

    test('does nothing on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final storage = RecordingStorage({'session.token': 'abc'});

      await migrateKeychainAccessibility(storage, keys);

      expect(storage.reads, isEmpty);
      expect(storage.writes, isEmpty);
    });
  });
}
