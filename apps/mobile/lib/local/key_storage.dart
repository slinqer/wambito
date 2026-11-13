import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/crypto.dart' show fromBase64Url, toBase64Url;
import '../storage/secure_storage.dart';

/// Where the phone keeps an account's encryption keys (spec 2026-11-12 section 3): the Keystore on
/// Android, the Keychain on iOS with `first_unlock_this_device` (never iCloud, never another
/// phone). Each name starts with `wambito.vault.<userId>.`:
/// - `dk.<v>`: the data key of version v, base64url;
/// - `current`: the current version;
/// - `device`: the X25519 device private key, base64url;
/// - `deviceWrapId` and `devicePublicKey`: the id and public key (base64url) of this phone's device
///   wrap, which the web keeps in its vault's meta.
///
/// The phone keeps the raw data keys, where the web keeps non-extractable derived `CryptoKey`s:
/// the Keychain and the Keystore are what protects them here.
class KeyStorage {
  KeyStorage([this._storage = appSecureStorage]);

  final FlutterSecureStorage _storage;

  /// Better Auth ids: letters, digits, `-`, `_` (as `assertUserId`). No `.`: one account's prefix
  /// is never a prefix of another account's names.
  static final RegExp _userId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static String _prefix(String userId) {
    if (!_userId.hasMatch(userId)) throw ArgumentError.value(userId, 'userId', 'not a user id');
    return 'wambito.vault.$userId.';
  }

  static String _dk(String userId, int v) {
    if (v < 0) throw ArgumentError.value(v, 'v', 'not a key version');
    return '${_prefix(userId)}dk.$v';
  }

  Future<Uint8List?> _readBytes(String name, int length) async {
    final text = await _storage.read(key: name);
    if (text == null) return null;
    try {
      final bytes = fromBase64Url(text);
      return bytes.length == length ? bytes : null;
    } on Object {
      return null;
    }
  }

  /// The data key of version [v], or `null` when it is not held (or not a 32-byte key).
  Future<Uint8List?> readDataKey(String userId, int v) => _readBytes(_dk(userId, v), 32);

  Future<void> writeDataKey(String userId, int v, Uint8List bytes) {
    if (bytes.length != 32) throw ArgumentError.value(bytes.length, 'bytes', 'not a data key');
    return _storage.write(key: _dk(userId, v), value: toBase64Url(bytes));
  }

  Future<void> deleteDataKey(String userId, int v) => _storage.delete(key: _dk(userId, v));

  /// The current key version, or `null` when this phone was never set up for [userId].
  Future<int?> current(String userId) async {
    final text = await _storage.read(key: '${_prefix(userId)}current');
    final v = text == null ? null : int.tryParse(text);
    return v == null || v < 0 ? null : v;
  }

  Future<void> setCurrent(String userId, int v) =>
      _storage.write(key: '${_prefix(userId)}current', value: '$v');

  /// The raw 32-byte X25519 private key of this phone's device wrap.
  Future<Uint8List?> devicePrivateKey(String userId) => _readBytes('${_prefix(userId)}device', 32);

  Future<void> setDevicePrivateKey(String userId, Uint8List bytes) {
    if (bytes.length != 32) throw ArgumentError.value(bytes.length, 'bytes', 'not a device key');
    return _storage.write(key: '${_prefix(userId)}device', value: toBase64Url(bytes));
  }

  /// The id of this phone's device wrap, kept at enroll.
  Future<String?> deviceWrapId(String userId) =>
      _storage.read(key: '${_prefix(userId)}deviceWrapId');

  /// The public key of this phone's device wrap, base64url as `/v2/keys` lists it.
  Future<String?> devicePublicKey(String userId) =>
      _storage.read(key: '${_prefix(userId)}devicePublicKey');

  Future<void> setDeviceWrap(String userId, {required String id, required String publicKey}) async {
    await _storage.write(key: '${_prefix(userId)}deviceWrapId', value: id);
    await _storage.write(key: '${_prefix(userId)}devicePublicKey', value: publicKey);
  }

  /// The key versions whose data key is kept for [userId], ascending.
  Future<List<int>> versions(String userId) async {
    final prefix = '${_prefix(userId)}dk.';
    final digits = RegExp(r'^\d+$');
    final found = <int>[
      for (final name in (await _storage.readAll()).keys)
        if (name.startsWith(prefix) && digits.hasMatch(name.substring(prefix.length)))
          ?int.tryParse(name.substring(prefix.length)),
    ];
    return found..sort();
  }

  /// Deletes every `wambito.vault.<userId>.*` item, and nothing of another account.
  Future<void> deleteAll(String userId) async {
    final prefix = _prefix(userId);
    final names = (await _storage.readAll()).keys.where((n) => n.startsWith(prefix)).toList();
    for (final name in names) {
      await _storage.delete(key: name);
    }
  }

  /// The prefixes [deleteAllVaultKeys] removes: every account's keys, and the cached
  /// `wambito.encryption.<userId>` (`plain` | `preview`) kept in the same storage.
  static const vaultKeyPrefixes = ['wambito.vault.', 'wambito.encryption.'];

  /// Deletes every `wambito.vault.*` and `wambito.encryption.*` item, of every account (keys left
  /// by an earlier install of the app; see `clearKeysAfterReinstall`). Nothing else is touched.
  Future<void> deleteAllVaultKeys() async {
    final names = (await _storage.readAll()).keys
        .where((n) => vaultKeyPrefixes.any(n.startsWith))
        .toList();
    for (final name in names) {
      await _storage.delete(key: name);
    }
  }
}
