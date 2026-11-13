import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/secure_storage.dart';
import 'db.dart' show vaultDirectoryName;

/// The Dart twin of `apps/web/app/local/stale-vaults.ts`. A vault outlives a session that ended
/// outside the sign-out (expired, signed out everywhere, the account deleted elsewhere): it waits
/// for its account to sign in again, which finds it and sends what was not sent. This deletes, of
/// every account but [keepUserId]:
/// - the vault file `wambito-vault-<id>.db` (and its SQLite side files) under `vault/` of the app's
///   support folder;
/// - its keys `wambito.vault.<id>.*` and its kept mode `wambito.encryption.<id>`;
/// - the kept `wambito.account`, when it is that account's.
///
/// Runs on every answer of `GET /v1/me` (a sign-in, a start) with the signed-in account, and on a
/// signed-out start with the account kept last (whose session ended without a sign-out). A sign-out
/// deletes its own vault itself. Never throws: what cannot be deleted now is left for the next time.
/// [forget] deletes one account's file and keys (`forgetVault`); [directory] is the vault folder.
Future<void> deleteStaleVaults(
  String? keepUserId, {
  required Future<void> Function(String userId) forget,
  FlutterSecureStorage storage = appSecureStorage,
  Future<String> Function()? directory,
}) async {
  final ids = <String>{};
  try {
    final folder = Directory(await (directory ?? _vaultDirectory)());
    if (folder.existsSync()) {
      for (final entry in folder.listSync()) {
        final id = _vaultFile.firstMatch(p.basename(entry.path))?.group(1);
        if (id != null) ids.add(id);
      }
    }
  } on Object {
    // No folder to list (no support folder yet, a test): the keys are still swept.
  }
  var names = const <String, String>{};
  try {
    names = await storage.readAll();
  } on Object {
    // Left for the next time.
  }
  for (final name in names.keys) {
    final id = (_vaultKey.firstMatch(name) ?? _modeKey.firstMatch(name))?.group(1);
    if (id != null) ids.add(id);
  }
  ids.remove(keepUserId);
  for (final id in ids) {
    try {
      await forget(id);
    } on Object {
      // Left for the next time.
    }
    try {
      await storage.delete(key: '$_modePrefix$id');
    } on Object {
      // Left for the next time.
    }
  }
  final kept = names[_accountKey];
  if (kept != null && _accountId(kept) != keepUserId) {
    try {
      await storage.delete(key: _accountKey);
    } on Object {
      // Left for the next time.
    }
  }
}

/// `wambito.account` (EncryptionStore.accountKey) and `wambito.encryption.` (its modeKey), named
/// here so lib/local does not depend on lib/vault.
const _accountKey = 'wambito.account';
const _modePrefix = 'wambito.encryption.';

final _vaultFile = RegExp(r'^wambito-vault-([A-Za-z0-9_-]{1,128})\.db(?:-journal|-wal|-shm)?$');
final _vaultKey = RegExp(r'^wambito\.vault\.([A-Za-z0-9_-]{1,128})\.');
final _modeKey = RegExp(r'^wambito\.encryption\.([A-Za-z0-9_-]{1,128})$');

String? _accountId(String raw) {
  try {
    final id = (jsonDecode(raw) as Map)['id'];
    return id is String ? id : null;
  } on Object {
    return null;
  }
}

/// The vault folder, without creating it (db.dart's [vaultDirectoryName]).
Future<String> _vaultDirectory() async =>
    p.join((await getApplicationSupportDirectory()).path, vaultDirectoryName);
