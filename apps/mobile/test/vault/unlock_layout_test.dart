// Which of the unlock screen's three layouts applies (spec 2026-11-20 section 1), the same cases as
// the web's apps/web/app/features/vault/unlock-layout.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/vault/unlock_layout.dart';

const key = UnlockAction.key;
const passkey = UnlockAction.passkey;
const pair = UnlockAction.pair;

UnlockPlacement layout({
  bool noPrfHere = false,
  bool passkeyWrap = false,
  bool passkeysSupported = false,
  bool canPair = false,
}) => unlockLayout(
  noPrfHere: noPrfHere,
  passkeyWrap: passkeyWrap,
  passkeysSupported: passkeysSupported,
  canPair: canPair,
);

void main() {
  test('no PRF here: the key is main, another passkey is under more only with a passkey wrap', () {
    expect(
      layout(noPrfHere: true, passkeysSupported: true, canPair: true, passkeyWrap: true),
      const UnlockPlacement(main: key, below: [pair], more: [passkey]),
    );
    expect(
      layout(noPrfHere: true, passkeysSupported: true, canPair: true),
      const UnlockPlacement(main: key, below: [pair], more: []),
    );
    expect(
      layout(noPrfHere: true, passkeysSupported: true, passkeyWrap: true),
      const UnlockPlacement(main: key, below: [], more: [passkey]),
    );
  });

  test('a passkey wrap and passkey support: the passkey is main, the key under more', () {
    expect(
      layout(passkeyWrap: true, passkeysSupported: true, canPair: true),
      const UnlockPlacement(main: passkey, below: [pair], more: [key]),
    );
    expect(
      layout(passkeyWrap: true, passkeysSupported: true),
      const UnlockPlacement(main: passkey, below: [], more: [key]),
    );
  });

  test('no passkey wrap: pairing is main, the key under more', () {
    expect(
      layout(passkeysSupported: true, canPair: true),
      const UnlockPlacement(main: pair, below: [], more: [key]),
    );
  });

  test('no passkey support with a wrap: pairing main, key under more', () {
    expect(
      layout(passkeyWrap: true, canPair: true),
      const UnlockPlacement(main: pair, below: [], more: [key]),
    );
  });

  test('nothing above more (no pairing, no passkey): the key is main and more is empty', () {
    expect(layout(), const UnlockPlacement(main: key, below: [], more: []));
    expect(layout(passkeysSupported: true), const UnlockPlacement(main: key, below: [], more: []));
  });
}
