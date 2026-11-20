import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/prf.dart';

/// The passkey sign-in's PRF, held in memory for the vault gate of the account it signed in to
/// (spec 2026-11-20 section 2): the phone's twin of the web's `keepSignInPrf` / `takeSignInPrf` /
/// `clearSignInPrf` (apps/web/app/local/prf.ts), shaped like [SignInRecoveryKey]. Never written,
/// never logged. One take: [take] hands it over once, to the gate of its account, which zeroes it
/// once used; another account's take gets nothing and the PRF is zeroed. A new [keep] or [clear] (a
/// sign-out) zeroes the one held.
class SignInPrf {
  String? _userId;
  PasskeyPrf? _passkey;

  /// Keeps [passkey] for [userId]'s gate, zeroing any earlier one. The holder now owns its bytes.
  void keep(String userId, PasskeyPrf passkey) {
    if (!identical(_passkey, passkey)) clear();
    _userId = userId;
    _passkey = passkey;
  }

  /// The kept PRF when it is [userId]'s, else null; nothing is kept afterwards either way. The
  /// caller owns what it gets and zeroes it.
  PasskeyPrf? take(String userId) {
    final passkey = _passkey;
    final owner = _userId;
    _passkey = null;
    _userId = null;
    if (passkey == null) return null;
    if (owner == userId) return passkey;
    _zero(passkey);
    return null;
  }

  /// Zeroes and drops a kept PRF.
  void clear() {
    final passkey = _passkey;
    _passkey = null;
    _userId = null;
    if (passkey != null) _zero(passkey);
  }

  static void _zero(PasskeyPrf passkey) => passkey.prf.fillRange(0, passkey.prf.length, 0);
}

/// The app's [SignInPrf] (memory only).
final signInPrfProvider = Provider<SignInPrf>((ref) {
  final held = SignInPrf();
  ref.onDispose(held.clear);
  return held;
});
