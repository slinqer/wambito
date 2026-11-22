// Twin of apps/web/app/features/settings/security-model.test.ts: Settings → Security's rows, from
// the wraps, this phone's device wrap id, the revoked list and the attestation checks.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart' show PasskeyItem;
import 'package:wambito/local/keys.dart' show WrapDto;
import 'package:wambito/settings/security/security_model.dart';
import 'package:wambito/ui/lk_icon_shapes.dart' show LkIconName;

WrapDto _wrap(String id, String kind, {String? ref, String? label, String? createdAt}) => WrapDto(
  id: id,
  kind: kind,
  ref: ref,
  keyV: 2,
  wrapped: 'w',
  label: label,
  createdAt: createdAt ?? '2026-10-01T10:00:00.000Z',
);

const _own = '01930000-0000-7000-8000-00000000000a';
const _laptop = '01930000-0000-7000-8000-00000000000b';
const _forged = '01930000-0000-7000-8000-00000000000c';
const _gone = '01930000-0000-7000-8000-00000000000d';

final _wraps = [
  _wrap('r', 'recovery'),
  _wrap(_laptop, 'device', label: 'Firefox on Linux', createdAt: '2026-10-03T10:00:00Z'),
  _wrap(_own, 'device', label: 'Pixel 9', createdAt: '2026-10-02T10:00:00Z'),
  _wrap(_forged, 'device', label: 'Safari on iOS', createdAt: '2026-10-04T10:00:00Z'),
  _wrap(_gone, 'device', label: 'Edge on Windows'),
  _wrap('p1', 'passkey', ref: 'cred-1'),
];

DeviceRows _rows() =>
    deviceRows(wraps: _wraps, ownId: _own, revoked: [_gone], verified: {_laptop, _gone});

PasskeyItem _passkey(String id, String credentialId) => PasskeyItem(
  id: id,
  credentialId: credentialId,
  createdAt: DateTime.utc(2026, 10, 2, 9),
  synced: true,
);

void main() {
  test('deviceIconFor: a laptop for computers, a phone otherwise', () {
    for (final name in [
      'MacBook',
      'Chrome on macOS',
      'Firefox on Linux',
      'Edge on Windows',
      'Chromebook Chrome OS',
      'Mi PC',
      'Laptop',
    ]) {
      expect(deviceIconFor(name), LkIconName.laptop, reason: name);
    }
    for (final name in ['Pixel 8', 'Safari on iOS', 'Huella', null]) {
      expect(deviceIconFor(name), LkIconName.phone, reason: '$name');
    }
  });

  group('deviceRows', () {
    test("this phone's device is marked and cannot be removed here", () {
      final rows = _rows();
      expect(rows.thisPhone?.id, _own);
      expect(rows.thisPhone?.label, 'Pixel 9');
      expect(rows.thisPhone?.thisPhone, isTrue);
      expect(rows.thisPhone?.removable, isFalse);
      expect(rows.others.map((d) => d.id), isNot(contains(_own)));
      expect(rows.others.every((d) => !d.thisPhone && d.removable), isTrue);
    });

    test('a device whose attestation fails is shown as "Not verified" with remove only', () {
      final rows = _rows();
      final forged = rows.others.firstWhere((d) => d.id == _forged);
      expect(forged.verified, isFalse);
      expect(forged.removable, isTrue);
      expect(rows.others.firstWhere((d) => d.id == _laptop).verified, isTrue);
      // this phone's own wrap needs no check: it opened DK here
      expect(rows.thisPhone?.verified, isTrue);
    });

    test('revoked ids are not listed', () {
      final rows = _rows();
      expect([rows.thisPhone?.id, ...rows.others.map((d) => d.id)], isNot(contains(_gone)));
      // only device wraps are devices, oldest first
      expect(rows.others.map((d) => d.id), [_laptop, _forged]);
    });

    test("without this phone's wrap there is no row for it", () {
      final rows = deviceRows(wraps: _wraps, ownId: null, revoked: [], verified: {});
      expect(rows.thisPhone, isNull);
    });
  });

  group('passkeyRows', () {
    test('passkeys join their wrap by credential id', () {
      final joined = passkeyRows([_passkey('pk-1', 'cred-1'), _passkey('pk-2', 'cred-2')], _wraps);
      expect(joined.map((p) => (p.item.id, p.unlocks)), [('pk-1', true), ('pk-2', false)]);
    });

    test('unknown wraps (not loaded, or a plain account) say nothing about unlocking', () {
      expect(passkeyRows([_passkey('pk-1', 'cred-1')], null).first.unlocks, isNull);
    });

    test('a passkey without a wrap is not protection', () {
      expect(hasPasskeyWrap(_wraps, 'cred-1'), isTrue);
      expect(hasPasskeyWrap(_wraps, 'cred-2'), isFalse);
      expect(anyPasskeyWrap(_wraps), isTrue);
      // a passkey is listed, but no wrap has it as `ref`: it signs in, it does not protect the data
      final withoutWrap = [_wrap('r', 'recovery'), _wrap(_own, 'device')];
      expect(anyPasskeyWrap(withoutWrap), isFalse);
      expect(passkeyRows([_passkey('pk-1', 'cred-1')], withoutWrap).first.unlocks, isFalse);
    });
  });
}
