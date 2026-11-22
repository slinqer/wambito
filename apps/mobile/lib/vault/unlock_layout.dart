// Which of the unlock screen's three layouts applies (spec 2026-11-20 section 1): the web's
// apps/web/app/features/vault/unlock-layout.ts.
import 'package:flutter/foundation.dart' show immutable, listEquals;

/// What the unlock screen can offer: the recovery key, a passkey, or another device (the pairing).
enum UnlockAction { key, passkey, pair }

/// What goes where: the main action, the ones below it, and those under "More options".
@immutable
class UnlockPlacement {
  const UnlockPlacement({required this.main, required this.below, required this.more});

  final UnlockAction main;
  final List<UnlockAction> below;
  final List<UnlockAction> more;

  @override
  bool operator ==(Object other) =>
      other is UnlockPlacement &&
      other.main == main &&
      listEquals(other.below, below) &&
      listEquals(other.more, more);

  @override
  int get hashCode => Object.hash(main, Object.hashAll(below), Object.hashAll(more));

  @override
  String toString() => 'UnlockPlacement(main: $main, below: $below, more: $more)';
}

/// What goes where on the unlock screen; pure.
///
/// [noPrfHere]: this phone's last passkey touch gave no PRF. [passkeyWrap]: the account has a
/// passkey wrap. [passkeysSupported]: the passkey button would be offered. [canPair]: "From another
/// device" is offered.
UnlockPlacement unlockLayout({
  required bool noPrfHere,
  required bool passkeyWrap,
  required bool passkeysSupported,
  required bool canPair,
}) {
  final below = [if (canPair) UnlockAction.pair];
  final passkeyWorks = passkeyWrap && passkeysSupported;
  if (noPrfHere) {
    return UnlockPlacement(
      main: UnlockAction.key,
      below: below,
      more: [if (passkeyWorks) UnlockAction.passkey],
    );
  }
  if (passkeyWorks) {
    return UnlockPlacement(
      main: UnlockAction.passkey,
      below: below,
      more: const [UnlockAction.key],
    );
  }
  if (canPair) {
    return const UnlockPlacement(main: UnlockAction.pair, below: [], more: [UnlockAction.key]);
  }
  return const UnlockPlacement(main: UnlockAction.key, below: [], more: []);
}
