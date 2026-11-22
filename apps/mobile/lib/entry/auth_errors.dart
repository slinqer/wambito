import 'dart:async';
import 'dart:io';

import '../api/auth_api.dart';
import '../l10n/app_localizations.dart';

/// The messages sign-in shows, the web's `errors.*` keys (apps/web/app/features/sign-in/auth.ts).
enum AuthError {
  invalidCode,
  invalidOrExpiredCode,
  tooManyAttempts,
  invalidEmail,
  tooManyRequests,
  signInNotAllowed,
  accountSuspended,
  guestSignupDisabled,
  emailTaken,
  tooManySignInAttempts,
  passkeyFailed,
  recoveryKeyInvalid,
  badRecoveryKey,
  networkError,
  internalError,
  generic,
}

/// What was being done when the call failed: a 429 means a different wait for each.
enum AuthAction { send, signIn }

/// Server codes → messages: Better Auth's (emailOTP and core), and the API's own, which the claim
/// routes share with sign-in.
const _codes = {
  'INVALID_OTP': AuthError.invalidCode,
  'OTP_EXPIRED': AuthError.invalidOrExpiredCode,
  'TOO_MANY_ATTEMPTS': AuthError.tooManyAttempts,
  'INVALID_EMAIL': AuthError.invalidEmail,
  'invalid_code': AuthError.invalidCode,
  'invalid_or_expired_code': AuthError.invalidOrExpiredCode,
  'too_many_attempts': AuthError.tooManyAttempts,
  'sign_in_not_allowed': AuthError.signInNotAllowed,
  'account_suspended': AuthError.accountSuspended,
  'guest_signup_disabled': AuthError.guestSignupDisabled,
  'email_taken': AuthError.emailTaken,
  // The recovery-key sign-in: a key that signs in nothing (the server's one answer, whatever the
  // reason, a `plain` account's key included), and one that does not parse (nothing was sent).
  'recovery_key_invalid': AuthError.recoveryKeyInvalid,
  'bad_recovery_key': AuthError.badRecoveryKey,
};

/// Errors that trying the same thing again (after a short wait) can fix.
const retryableErrors = {
  AuthError.networkError,
  AuthError.internalError,
  AuthError.tooManySignInAttempts,
};

/// Errors about the account, the same whatever the sign-in path: the passkey and the link keep them.
const _accountErrors = {AuthError.accountSuspended};

/// The message for a failed auth call, as the web picks it.
AuthError authErrorFor(AuthFailure failure, AuthAction action) {
  if (failure.status == 0) return AuthError.networkError;
  if (failure.status == 429) {
    return action == AuthAction.send ? AuthError.tooManyRequests : AuthError.tooManySignInAttempts;
  }
  if (failure.status >= 500) return AuthError.internalError;
  return _codes[failure.code] ?? AuthError.generic;
}

/// The message for anything a sign-in can throw besides an [AuthFailure]: a lost connection or a
/// timeout outside Dio says so; anything else (a storage error, a bug) is "something went wrong".
/// The screen stays usable either way.
AuthError unexpectedErrorFor(Object error) => switch (error) {
  SocketException() ||
  TimeoutException() ||
  HttpException() ||
  TlsException() => AuthError.networkError,
  _ => AuthError.generic,
};

/// [unexpectedErrorFor] for the passkey prompt: what is not a lost connection suggests the email.
AuthError unexpectedPasskeyErrorFor(Object error) {
  final reason = unexpectedErrorFor(error);
  return reason == AuthError.networkError ? reason : AuthError.passkeyFailed;
}

/// The message for a passkey sign-in that did not work, or null when the person just closed the
/// phone's prompt (nothing to explain).
AuthError? passkeyErrorFor(AuthFailure failure) {
  if (failure.code == 'AUTH_CANCELLED') return null;
  final error = authErrorFor(failure, AuthAction.signIn);
  return retryableErrors.contains(error) || _accountErrors.contains(error)
      ? error
      : AuthError.passkeyFailed;
}

/// The message for a magic link that did not sign in: whatever was wrong with the code, the
/// person can only ask for a new one, unless retrying can help.
AuthError linkErrorFor(AuthFailure failure) {
  final error = authErrorFor(failure, AuthAction.signIn);
  return retryableErrors.contains(error) || _accountErrors.contains(error)
      ? error
      : AuthError.invalidOrExpiredCode;
}

/// Whether [error] is about the code itself (the field is marked and emptied).
bool isCodeError(AuthError error) =>
    error == AuthError.invalidCode ||
    error == AuthError.invalidOrExpiredCode ||
    error == AuthError.tooManyAttempts;

extension AuthErrorMessage on AuthError {
  String message(AppLocalizations l10n) => switch (this) {
    AuthError.invalidCode => l10n.errorInvalidCode,
    AuthError.invalidOrExpiredCode => l10n.errorInvalidOrExpiredCode,
    AuthError.tooManyAttempts => l10n.errorTooManyAttempts,
    AuthError.invalidEmail => l10n.errorInvalidEmail,
    AuthError.tooManyRequests => l10n.errorTooManyRequests,
    AuthError.signInNotAllowed => l10n.errorSignInNotAllowed,
    AuthError.accountSuspended => l10n.errorAccountSuspended,
    AuthError.guestSignupDisabled => l10n.errorGuestSignupDisabled,
    AuthError.emailTaken => l10n.errorEmailTaken,
    AuthError.tooManySignInAttempts => l10n.errorTooManySignInAttempts,
    AuthError.passkeyFailed => l10n.errorPasskeyFailed,
    AuthError.recoveryKeyInvalid => l10n.errorRecoveryKeyInvalid,
    AuthError.badRecoveryKey => l10n.vaultUnlockErrorBadKey,
    AuthError.networkError => l10n.errorNetwork,
    AuthError.internalError => l10n.errorInternal,
    AuthError.generic => l10n.errorGeneric,
  };
}

/// Good enough to catch typos; the server has the final word (the web's rule).
final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// An email as the server reads it: trimmed and lowercased.
String normalizeEmail(String raw) => raw.trim().toLowerCase();
