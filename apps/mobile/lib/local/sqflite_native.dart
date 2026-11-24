// sqflite's native side, shared by every Flutter engine of the process (the app's and a headless
// run's): one map of open connections and one pool of database threads, neither tied to an engine.
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'db.dart' show defaultVaultDirectory, vaultFileName;
import 'vault_lock.dart';

/// sqflite's own channel (`Constant.PLUGIN_KEY`); every engine of the process reaches the same
/// native state through it.
const sqflitePluginChannel = MethodChannel('com.tekartik.sqflite');

/// Closes the background connections (`singleInstance: false`) of [userId]'s vault that no run owns
/// any more, and returns how many. A headless engine destroyed by its budget leaves its connection
/// open in sqflite's map (it is never closed on an engine's detach), and inside a transaction it
/// keeps the file's write lock until the process ends: every read of the app then fails with
/// `database is locked`. Its transaction is rolled back, then it is closed.
///
/// Only under the vault's lease (holder `app`): taken here, or already held by this engine (the
/// app's sync takes it before its writes, which are the first to meet the lock). A live run holds
/// it (renewed by its sync), so then nothing is touched; and no new run can start while the
/// connections close. A plugin that
/// cannot list its connections (another platform's) closes nothing.
Future<int> closeOrphanVaultConnections(
  String userId, {
  String? directory,
  MethodChannel channel = sqflitePluginChannel,
}) async {
  final dir = directory ?? await defaultVaultDirectory();
  final lease = await tryLease(userId, holder: 'app', directory: dir);
  // Taken already by this engine (the app's own sync, whose write met the lock): ours to use, and
  // left to its holder to release.
  if (lease == null && !await leaseHeldHere(userId, holder: 'app', directory: dir)) return 0;
  try {
    final path = p.join(dir, vaultFileName(userId));
    final info = await channel.invokeMethod<Object?>('debug', {'cmd': 'get'});
    final databases = info is Map ? info['databases'] : null;
    if (databases is! Map) return 0;
    var closed = 0;
    for (final MapEntry(:key, :value) in databases.entries) {
      final id = int.tryParse('$key');
      if (id == null || value is! Map) continue;
      if (value['path'] != path || value['singleInstance'] != false) continue;
      // An open transaction keeps Android's connection checked out, so closing alone never frees
      // it (the pool closes it "once released"): roll it back first, as sqflite's forced statement
      // (transaction id -1), which runs even inside another caller's transaction.
      try {
        await channel.invokeMethod<void>('execute', {
          'id': id,
          'sql': 'ROLLBACK',
          'arguments': <Object?>[],
          'inTransaction': false,
          'transactionId': -1,
        });
      } on PlatformException {
        // No transaction was open.
      }
      await channel.invokeMethod<void>('closeDatabase', {'id': id});
      closed++;
    }
    return closed;
  } on PlatformException {
    return 0;
  } on MissingPluginException {
    return 0;
  } finally {
    await lease?.release();
  }
}
