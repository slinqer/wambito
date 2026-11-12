import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/secure_storage.dart';

/// Where the app's keyed text settings are kept: the server URL, the theme and the language.
/// The app uses `flutter_secure_storage` (already in the app for the session, so no new
/// dependency); tests use memory.
abstract interface class SettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSettingsStore implements SettingsStore {
  const SecureSettingsStore([this._storage = appSecureStorage]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final settingsStoreProvider = Provider<SettingsStore>((ref) => const SecureSettingsStore());

const serverUrlKey = 'setting.server';
const themeModeKey = 'setting.theme';
const localeKey = 'setting.locale';
