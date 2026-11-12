import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/records.dart' show Json;
import '../crypto/records.dart' show RecordType;

/// The SQLite file of the encrypted vault: the Dart twin of `apps/web/app/local/db.ts`. Everything
/// the vault keeps for one account lives in `wambito-vault-<userId>.db`. The keys are not in it
/// (the web's `keys` store): the phone keeps them in secure storage.

const outboxTable = 'outbox';
const metaTable = 'meta';
const quarantineTable = 'quarantine';

String vaultFileName(String userId) => 'wambito-vault-$userId.db';

/// The table of a record type. `transaction` is an SQL keyword, so names are always quoted.
String recordTable(RecordType type) => type.name;

String quoted(String name) => '"$name"';

/// A local change waiting to be pushed: one entry per record id. Same fields as `db.ts`.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.type,
    required this.baseVersion,
    required this.deleted,
    required this.touched,
    required this.seq,
    this.park,
    this.abandoned = false,
    this.setAside,
    this.reseal = false,
  });

  final String id;
  final RecordType type;

  /// The server version the change is based on; null for a record the server has never seen.
  final int? baseVersion;
  final bool deleted;

  /// Body fields changed since the last push (the union over merged writes).
  final List<String> touched;

  /// Bumped by every local write: the engine acks only the write it read.
  final int seq;

  /// Set by the engine when this write keeps failing: not pushed again before `park.until`. Any
  /// local write of the id clears it.
  final OutboxPark? park;

  /// Set when the engine gave up on this write: never pushed again, the server's copy replaces it.
  final bool abandoned;

  /// Set by a resync's wipe: the local body at that moment, to be written again onto the fresh
  /// server copy after the full download.
  final SetAside? setAside;

  /// Added by the upgrade pass: the record's unchanged body, to be sealed under the current key
  /// version. A local write of the id turns it into an ordinary edit.
  final bool reseal;

  OutboxEntry copyWith({
    int? baseVersion,
    List<String>? touched,
    OutboxPark? park,
    bool? abandoned,
    SetAside? setAside,
  }) => OutboxEntry(
    id: id,
    type: type,
    baseVersion: baseVersion ?? this.baseVersion,
    deleted: deleted,
    touched: touched ?? this.touched,
    seq: seq,
    park: park ?? this.park,
    abandoned: abandoned ?? this.abandoned,
    setAside: setAside ?? this.setAside,
    reseal: reseal,
  );
}

class OutboxPark {
  const OutboxPark({required this.attempts, required this.lastError, required this.until});

  final int attempts;

  /// A short code (`rejected_422`, `conflict_unreadable`, ...), never a body.
  final String lastError;

  /// Epoch ms before which the engine does not push it again.
  final int until;

  Json toJson() => {'attempts': attempts, 'lastError': lastError, 'until': until};

  static OutboxPark fromJson(Json j) => OutboxPark(
    attempts: j['attempts']! as int,
    lastError: j['lastError']! as String,
    until: j['until']! as int,
  );
}

/// The body a change had when a resync set it aside; null when the record had no row.
class SetAside {
  const SetAside(this.body);

  final Json? body;
}

/// A record that failed to open or validate: counted, never shown, never overwritten.
class QuarantineEntry {
  const QuarantineEntry({
    required this.id,
    required this.type,
    required this.version,
    required this.reason,
    this.keyV,
  });

  final String id;
  final RecordType type;
  final int version;
  final String reason;

  /// The key version it was sealed under.
  final int? keyV;
}

/// What the sync engine reads about a record: the plaintext and its envelope.
class RawRecord {
  const RawRecord({
    required this.id,
    required this.body,
    required this.deleted,
    required this.version,
    required this.keyV,
  });

  final String id;
  final Json body;
  final bool deleted;

  /// The server's version; 0 until the record has been pushed.
  final int version;

  /// The key version the server copy was sealed under.
  final int keyV;
}

/// The folder the vault files live in: `vault` in the app's private support folder (Android
/// `files/vault`). One folder of its own, so the backup rules (Android XML) and the iOS exclusion
/// cover the file and its SQLite side files (`-journal`, `-wal`, `-shm`) by naming it.
Future<String> defaultVaultDirectory() async {
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, vaultDirectoryName));
  await dir.create(recursive: true);
  return dir.path;
}

/// The vault folder's name under the support folder; `res/xml/backup_rules.xml` names it too.
const vaultDirectoryName = 'vault';

Future<String> _path(String userId, String? directory) async =>
    p.join(directory ?? await defaultVaultDirectory(), vaultFileName(userId));

const _recordColumns = '''
  id TEXT PRIMARY KEY,
  seq INTEGER NOT NULL,
  body TEXT NOT NULL,
  deleted INTEGER NOT NULL,
  version INTEGER NOT NULL,
  key_v INTEGER NOT NULL''';

Future<void> _create(Database db, int version) async {
  for (final type in RecordType.values) {
    final extra = type == RecordType.transaction
        ? ',\n  date TEXT,\n  category_id TEXT,\n  amount INTEGER'
        : '';
    await db.execute('CREATE TABLE ${quoted(recordTable(type))} (\n$_recordColumns$extra)');
  }
  await db.execute('CREATE INDEX transaction_date ON "transaction" (date)');
  await db.execute('CREATE INDEX transaction_category ON "transaction" (category_id)');
  await db.execute('CREATE INDEX transaction_amount ON "transaction" (amount)');
  await db.execute('''
CREATE TABLE $outboxTable (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  base_version INTEGER,
  deleted INTEGER NOT NULL,
  touched TEXT NOT NULL,
  seq INTEGER NOT NULL,
  park TEXT,
  abandoned INTEGER NOT NULL,
  set_aside TEXT,
  reseal INTEGER NOT NULL)''');
  await db.execute('CREATE INDEX outbox_seq ON $outboxTable (seq)');
  await db.execute('CREATE TABLE $metaTable (key TEXT PRIMARY KEY, value TEXT)');
  await db.execute('''
CREATE TABLE $quarantineTable (
  type TEXT NOT NULL,
  id TEXT NOT NULL,
  version INTEGER NOT NULL,
  reason TEXT NOT NULL,
  key_v INTEGER,
  PRIMARY KEY (type, id, version))''');
}

/// Opens (creating it on the first run) the vault file of [userId]. [directory] and [factory] are
/// for tests; the app leaves them out.
Future<Database> openVault(String userId, {String? directory, DatabaseFactory? factory}) async {
  final path = await _path(userId, directory);
  return (factory ?? databaseFactory).openDatabase(
    path,
    options: OpenDatabaseOptions(version: 1, onCreate: _create),
  );
}

/// Signing out: removes the file, the records and the outbox in it. Close the store first.
Future<void> deleteVault(String userId, {String? directory, DatabaseFactory? factory}) async {
  await (factory ?? databaseFactory).deleteDatabase(await _path(userId, directory));
}
