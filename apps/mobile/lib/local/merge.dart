// Carrying one vault's records into another: a new user's vault adopting an old one (the offline
// start, a deleted user's data; ruling 7) and the merge into an existing account (spec 7.2 step 5,
// rulings 11 and 12). Every record lands as a local write of the target, so the target's outbox
// pushes it with no base version, sealed under the target's user id and data key.
import '../core/records.dart' show Json;
import '../crypto/records.dart' show RecordType;
import 'captures.dart' show merchantRecordId;
import 'ids.dart';
import 'store.dart';

enum CarryMode {
  /// Into a new user's empty vault: every record as it is.
  adopt,

  /// Into an existing account's vault: its categories, accounts, settings, budgets and merchants
  /// win where the phone's match them.
  merge,
}

class CarryReport {
  const CarryReport({required this.written, required this.dropped, required this.remapped});

  /// Records put into the target (a carried tombstone counts).
  final int written;

  /// The source's live records left out: matched, the phone's settings in a merge, a budget or a
  /// merchant the target already has.
  final int dropped;

  /// A source id → the target id that now stands for it (matched categories and accounts,
  /// re-keyed merchants and settings).
  final Map<String, String> remapped;
}

/// The currency of [store]'s settings record, null when it has none.
Future<String?> currencyOf(FinanceStore store) async {
  final all = await store.list(RecordType.settings);
  return all.isEmpty ? null : all.first.body['currency'] as String?;
}

/// The folding that makes two category (or account) names the same one.
String foldedName(String name) => name.trim().toLowerCase();

String _seedId(String userId, String name) => uuidv5(uuidv5(seedNamespace, userId), name);

/// Copies [from]'s live records into [into] in one transaction of [into]. Tombstones stay behind,
/// except a deleted occurrence of a carried recurrence: it is what keeps the rule from making that
/// month's occurrence again, so it is carried as a tombstone (with its body). A second run writes
/// the same bodies under the same ids: the target's own records are told apart from earlier copies
/// by id, since the source's ids never exist in another user's vault.
Future<CarryReport> carryRecords(
  FinanceStore from,
  FinanceStore into, {
  required CarryMode mode,
  required String intoUserId,
}) async {
  final source = {for (final type in RecordType.values) type: await from.list(type)};
  final liveRules = {for (final r in source[RecordType.recurrence]!) r.id};
  final deletedOccurrences = [
    for (final r in await from.list(
      RecordType.transaction,
      const ReadOptions(includeDeleted: true),
    ))
      if (r.deleted &&
          r.body['occurrenceMonth'] != null &&
          liveRules.contains(r.body['recurrenceId']))
        r,
  ];
  final merge = mode == CarryMode.merge;

  return into.transaction((tx) async {
    var written = 0;
    var dropped = 0;
    final remapped = <String, String>{};

    /// The target's records of [type], without earlier copies of the source's.
    Future<List<StoredRecord>> theirs(RecordType type) async {
      final copied = {for (final r in source[type]!) r.id};
      return [
        for (final r in await tx.list(type))
          if (!copied.contains(r.id)) r,
      ];
    }

    Future<void> put(RecordType type, String id, Json body) async {
      await tx.put(type, id, body);
      written += 1;
    }

    String? mapped(Object? id) => id is String ? (remapped[id] ?? id) : null;

    // Categories: one of the account's that is not archived, of the same folded name and kind,
    // stands for the phone's; same name and another kind keeps the phone's as "<name> 2".
    final accountCategories = merge
        ? [
            for (final c in await theirs(RecordType.category))
              if (c.body['archivedAt'] == null) c,
          ]
        : const <StoredRecord>[];
    final accountNames = {for (final c in accountCategories) foldedName(c.body['name']! as String)};
    final usedNames = {
      ...accountNames,
      for (final c in source[RecordType.category]!) foldedName(c.body['name']! as String),
    };
    for (final c in source[RecordType.category]!) {
      final name = c.body['name']! as String;
      final key = foldedName(name);
      if (merge) {
        final match = accountCategories
            .where((a) => foldedName(a.body['name']! as String) == key)
            .where((a) => a.body['kind'] == c.body['kind'])
            .firstOrNull;
        if (match != null) {
          remapped[c.id] = match.id;
          dropped += 1;
          continue;
        }
        if (accountNames.contains(key)) {
          var n = 2;
          while (usedNames.contains(foldedName('${name.trim()} $n'))) {
            n += 1;
          }
          final renamed = '${name.trim()} $n';
          usedNames.add(foldedName(renamed));
          await put(RecordType.category, c.id, {...c.body, 'name': renamed});
          continue;
        }
      }
      await put(RecordType.category, c.id, c.body);
    }

    // Accounts: matched by the same folded name.
    final accountAccounts = merge ? await theirs(RecordType.account) : const <StoredRecord>[];
    for (final a in source[RecordType.account]!) {
      final key = foldedName(a.body['name']! as String);
      final match = accountAccounts
          .where((b) => foldedName(b.body['name']! as String) == key)
          .firstOrNull;
      if (match != null) {
        remapped[a.id] = match.id;
        dropped += 1;
        continue;
      }
      await put(RecordType.account, a.id, a.body);
    }

    // Settings: a merge keeps the account's; an adoption moves the phone's to the new user's seed
    // id, without what belonged to the old user's keys (a saved recovery key, removed devices).
    for (final (i, s) in source[RecordType.settings]!.indexed) {
      if (merge || i > 0) {
        dropped += 1;
        continue;
      }
      final id = _seedId(intoUserId, 'settings');
      if (id != s.id) remapped[s.id] = id;
      await put(RecordType.settings, id, {
        ...s.body,
        'recoveryKeySavedAt': null,
        'revokedDevices': <Object?>[],
      });
    }

    // Budgets: a phone budget only where the account has none for that category.
    final budgeted = {
      for (final b in merge ? await theirs(RecordType.budget) : const <StoredRecord>[])
        b.body['categoryId'],
    };
    for (final b in source[RecordType.budget]!) {
      final categoryId = mapped(b.body['categoryId']);
      if (budgeted.contains(categoryId)) {
        dropped += 1;
        continue;
      }
      await put(RecordType.budget, b.id, {...b.body, 'categoryId': categoryId});
    }

    // Recurrences and transactions (their occurrences too) keep their ids.
    for (final r in source[RecordType.recurrence]!) {
      await put(RecordType.recurrence, r.id, {
        ...r.body,
        'categoryId': mapped(r.body['categoryId']),
      });
    }
    Json repointed(Json t) => {
      ...t,
      'categoryId': mapped(t['categoryId']),
      'accountId': mapped(t['accountId']),
    };
    for (final t in source[RecordType.transaction]!) {
      await put(RecordType.transaction, t.id, repointed(t.body));
    }
    for (final t in deletedOccurrences) {
      await put(RecordType.transaction, t.id, repointed(t.body));
      await tx.delete(RecordType.transaction, t.id);
    }

    // Merchants: their ids derive from the user, so they move to the target's; the target's own
    // record of the same merchant wins.
    for (final m in source[RecordType.merchant]!) {
      final id = merchantRecordId(intoUserId, m.body['merchantKey']! as String);
      remapped[m.id] = id;
      if (await tx.get(RecordType.merchant, id) != null) {
        dropped += 1;
        continue;
      }
      await put(RecordType.merchant, id, {...m.body, 'categoryId': mapped(m.body['categoryId'])});
    }

    return CarryReport(written: written, dropped: dropped, remapped: remapped);
  });
}
