// What Settings does with the person's passkeys: the web's apps/web/app/features/settings/passkeys.ts
// (`PasskeysApi`, `livePasskeys`) and `passkeyOutcome`/`addPasskey` of apps/web/app/auth/passkey.ts, on
// the phone: Better Auth's routes for the list and the delete, Credential Manager for the new one.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_api.dart';
import '../api/session.dart';
import '../local/prf.dart';
import '../vault/vault_providers.dart' show touchPasskey;

export '../api/auth_api.dart' show PasskeyItem;

/// What adding a passkey came to; `cancelled` is the person closing the phone's prompt.
enum PasskeyOutcome { added, cancelled, failed }

/// What a new passkey's PRF is for: an encrypted account wraps its data key under it (stage 2b), so
/// the passkey opens the data too. Twin of the web's `PasskeyPrfUse` (apps/web/app/auth/passkey.ts).
class PasskeyPrfUse {
  const PasskeyPrfUse({required this.explainSecondTouch, required this.keep});

  /// Says why the phone asks for a second touch, before it does.
  final VoidCallback explainSecondTouch;

  /// Takes the new passkey's PRF (the wrap is made from it). The caller zeroes the bytes.
  final Future<void> Function(PasskeyPrf passkey) keep;
}

/// What the settings card asks of passkeys, as an interface so tests can stand in for Better Auth
/// and Credential Manager (the web passes the same four as a prop).
abstract interface class SettingsPasskeys {
  /// Whether this phone can make one (Android 14 or newer with a passkey manager). Listing and
  /// deleting work anyway.
  Future<bool> supported();

  /// The signed-in account's passkeys, oldest first; throws when they cannot be read.
  Future<List<PasskeyItem>> list();

  /// Makes one: the phone asks for the fingerprint or face. Never throws. With [prf] (an encrypted
  /// account whose vault is open), the new passkey's PRF also goes to `prf.keep`: from the
  /// registration itself, else from a second touch (explained first) when the registration said the
  /// passkey supports PRF but gave no output. A passkey with no PRF still signs in.
  Future<PasskeyOutcome> add({PasskeyPrfUse? prf});

  /// Deletes one; throws when the server says no.
  Future<void> remove(String id);
}

/// How the phone's and the server's answers to an add come out: closing the prompt is not a failure
/// worth a message, and a passkey the phone already has counts as added (the web's `passkeyOutcome`).
PasskeyOutcome passkeyOutcome(Object? error) {
  if (error == null) return PasskeyOutcome.added;
  if (error is AuthFailure) {
    switch (error.code) {
      case 'AUTH_CANCELLED':
        return PasskeyOutcome.cancelled;
      case 'ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED':
        return PasskeyOutcome.added;
    }
  }
  return PasskeyOutcome.failed;
}

/// [SettingsPasskeys] over the session's token, the auth server and the phone's Credential Manager.
class LiveSettingsPasskeys implements SettingsPasskeys {
  LiveSettingsPasskeys(this._ref);

  final Ref _ref;

  /// The session's token; none means the session is gone.
  String _token() {
    final token = _ref.read(sessionProvider).stored?.token;
    if (token == null) throw const AuthFailure(code: 'UNAUTHORIZED', status: 401);
    return token;
  }

  /// [call], ending the session when the server no longer knows it (as the other screens do).
  Future<T> _asked<T>(Future<T> Function(String token) call) async {
    try {
      return await call(_token());
    } on AuthFailure catch (failure) {
      if (failure.status == 401) {
        unawaited(_ref.read(sessionProvider.notifier).signOut(discardGuest: true));
      }
      rethrow;
    }
  }

  @override
  Future<bool> supported() => _ref.read(passkeysProvider).supported();

  @override
  Future<List<PasskeyItem>> list() =>
      _asked((token) => _ref.read(authApiProvider).listPasskeys(token));

  @override
  Future<PasskeyOutcome> add({PasskeyPrfUse? prf}) async {
    if (prf == null) {
      try {
        await _ref.read(sessionProvider.notifier).registerPasskey();
        return PasskeyOutcome.added;
      } on Object catch (error) {
        return passkeyOutcome(error);
      }
    }
    final String? attestation;
    try {
      attestation = await _register();
    } on Object catch (error) {
      return passkeyOutcome(error);
    }
    if (attestation != null) {
      try {
        final passkey = await _prfOfNewPasskey(attestation, prf);
        if (passkey != null) {
          try {
            await prf.keep(passkey);
          } finally {
            passkey.prf.fillRange(0, passkey.prf.length, 0);
          }
        }
      } on Object {
        // The passkey was added and signs in; it only does not open the data yet.
      }
    }
    return PasskeyOutcome.added;
  }

  /// Registers a passkey asking for its PRF too; the phone's attestation, or null when the phone
  /// already had it (nothing new to read).
  Future<String?> _register() async {
    final notifier = _ref.read(sessionProvider.notifier);
    await notifier.ready;
    final token = _token();
    final auth = _ref.read(authApiProvider);
    final challenge = await auth.passkeyRegisterOptions(token);
    final options = (jsonDecode(challenge.optionsJson) as Map).cast<String, Object?>();
    final extensions = {
      ...?(options['extensions'] as Map?)?.cast<String, Object?>(),
      ...prfExtension(),
    };
    final String attestation;
    try {
      attestation = await _ref
          .read(passkeysProvider)
          .create(jsonEncode({...options, 'extensions': extensions}));
    } on AuthFailure catch (error) {
      if (error.code == 'ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED') return null;
      rethrow;
    }
    await auth.passkeyRegister(token, challenge, attestation);
    return attestation;
  }

  /// The new passkey's PRF: from the registration, else (when it said `prf.enabled` without an
  /// output) from a second touch of that passkey only. A second touch that is cancelled or gives
  /// nothing leaves the passkey without a wrap.
  Future<PasskeyPrf?> _prfOfNewPasskey(String attestation, PasskeyPrfUse use) async {
    final decoded = jsonDecode(attestation);
    if (decoded is! Map) return null;
    final id = decoded['id'];
    final results = decoded['clientExtensionResults'];
    final extensionResults = results is Map ? results.cast<String, Object?>() : <String, Object?>{};
    final bytes = readPrf(extensionResults);
    if (id is! String) {
      bytes?.fillRange(0, bytes.length, 0);
      return null;
    }
    if (bytes != null) return PasskeyPrf(credentialId: id, prf: bytes);
    if (!prfEnabledWithoutResults(extensionResults)) return null;
    use.explainSecondTouch();
    try {
      return await touchPasskey(_ref.read(authApiProvider), _ref.read(passkeysProvider), [id]);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> remove(String id) =>
      _asked((token) => _ref.read(authApiProvider).deletePasskey(token, id));
}

final settingsPasskeysProvider = Provider<SettingsPasskeys>(LiveSettingsPasskeys.new);
