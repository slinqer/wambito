// Twin of apps/web/app/features/settings/security-model.ts: Settings → Security's rows, from
// `GET /v2/keys`, this phone's device wrap id, `settings.revokedDevices`, the attestation checks and
// the passkey list. Pure: the screen loads the inputs (security_api.dart).
import 'package:flutter/foundation.dart';

import '../../api/auth_api.dart' show PasskeyItem;
import '../../local/keys.dart' show WrapDto;

@immutable
class DeviceRow {
  const DeviceRow({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.thisPhone,
    required this.verified,
    required this.removable,
  });

  final String id;
  final String? label;
  final String? createdAt;

  /// This phone's own device: marked, and never removable from here.
  final bool thisPhone;

  /// Its attestation checks out under the data key; else shown as "Not verified".
  final bool verified;
  final bool removable;
}

/// This phone's device and the others, oldest first.
typedef DeviceRows = ({DeviceRow? thisPhone, List<DeviceRow> others});

/// A passkey with whether a passkey wrap has its credential as `ref`; null when the wraps are
/// unknown.
@immutable
class PasskeyRow {
  const PasskeyRow(this.item, this.unlocks);

  final PasskeyItem item;
  final bool? unlocks;
}

/// This phone's device and the others, oldest first. Revoked ids (removed earlier, whatever the
/// server still lists) are left out; a device whose attestation failed can only be removed.
DeviceRows deviceRows({
  required List<WrapDto> wraps,
  required String? ownId,
  required List<String> revoked,
  required Set<String> verified,
}) {
  final revokedIds = revoked.toSet();
  DeviceRow? thisPhone;
  final others = <DeviceRow>[];
  for (final wrap in wraps) {
    if (wrap.kind != 'device' || revokedIds.contains(wrap.id)) continue;
    final own = wrap.id == ownId;
    final row = DeviceRow(
      id: wrap.id,
      label: wrap.label,
      createdAt: wrap.createdAt,
      thisPhone: own,
      // this phone's own wrap opened the data key here: nothing to check
      verified: own || verified.contains(wrap.id),
      removable: !own,
    );
    if (own) {
      thisPhone = row;
    } else {
      others.add(row);
    }
  }
  // ISO times sort as text; `sort` is not stable, so equal ones keep the server's order by index.
  final indexed = [for (final (i, row) in others.indexed) (i, row)]
    ..sort((a, b) {
      final byTime = (a.$2.createdAt ?? '').compareTo(b.$2.createdAt ?? '');
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return (thisPhone: thisPhone, others: [for (final (_, row) in indexed) row]);
}

/// Each passkey with whether its wrap exists (joined by credential id, the wrap's `ref`).
List<PasskeyRow> passkeyRows(List<PasskeyItem> passkeys, List<WrapDto>? wraps) {
  final refs = wraps == null
      ? null
      : {
          for (final wrap in wraps)
            if (wrap.kind == 'passkey' && wrap.ref != null) wrap.ref!,
        };
  return [
    for (final item in passkeys)
      PasskeyRow(
        item,
        refs == null || item.credentialId == null ? null : refs.contains(item.credentialId),
      ),
  ];
}

/// Whether a passkey wrap has [credentialId] as its `ref`: a passkey that signs in but has no wrap
/// does not protect the data (phone-first 5.2).
bool hasPasskeyWrap(List<WrapDto> wraps, String credentialId) =>
    wraps.any((w) => w.kind == 'passkey' && w.ref == credentialId);

/// Whether any passkey wrap exists.
bool anyPasskeyWrap(List<WrapDto> wraps) => wraps.any((w) => w.kind == 'passkey' && w.ref != null);
