// Deleting the account: the web's DeleteAccount.tsx (`DELETE /v1/me`, sign out, and the landing) and
// Review Focus 5 of Stage 3c. The web has a cookie and a query cache to forget; the phone keeps
// more, and none of it may outlive the account: the session, the home cache, the widget's figures,
// the notices (their jobs and any already posted), the voice models, the copies of an export made
// for the share sheet, the welcome's draft, the answers to the passkey offer and the cards put
// away on home.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/passkey_offer.dart';
import '../api/session.dart';
import '../capture/models_download.dart';
import '../feedback/stored_flag.dart';
import '../files/files_channel.dart';
import '../home/home_controller.dart';
import '../home/home_repository.dart';
import '../home/nudges.dart';
import '../notices/notice_platform.dart';
import '../vault/unlock_hint.dart';
import '../welcome/welcome_controller.dart';
import 'account_repository.dart';
import 'profile_settings.dart';

/// The server did not know the session on the first try (it had expired), so the account was NOT
/// deleted. The phone has signed out; the person must sign in again to delete it.
class AccountSessionExpired implements Exception {
  const AccountSessionExpired();
}

/// Deletes the signed-in account and clears everything of it on the phone.
///
/// It is owned by the app, not by the sheet that asked: a sheet closed in the middle of the call does
/// not stop it, and the phone is cleared whether or not anything is still on screen to see it.
class AccountDeletion {
  AccountDeletion(this._ref);

  final Ref _ref;
  Future<void>? _inFlight;

  /// The session token of an attempt whose answer may have been lost (no answer at all, or a 5xx):
  /// the account may be gone already, so a later 401 with that same token means it is.
  String? _mayBeGoneFor;

  /// `DELETE /v1/me` and then the phone. A failure that is the server's refusal or no answer is
  /// thrown as a [HomeFailure] and changes nothing, here or there. A 401 is the server saying it no
  /// longer knows the session. After an earlier attempt of this flow lost its answer, the account is
  /// gone, and the phone is cleared as after a delete. On a first attempt it means the session had
  /// expired and the account still exists: the phone signs out and throws [AccountSessionExpired],
  /// so the person is told plainly that nothing was deleted.
  ///
  /// A call while one is under way gets that one's answer (the same success, the same failure): it
  /// never sends a second DELETE, and never reports a success that has not happened.
  Future<void> delete() => _inFlight ??= _delete().whenComplete(() => _inFlight = null);

  Future<void> _delete() async {
    // Before the account is gone: who it is, for what is kept under its id.
    final id = await _accountId();
    final token = _ref.read(sessionProvider).stored?.token;
    try {
      await _ref.read(accountRepositoryProvider).deleteAccount();
    } on HomeFailure catch (failure) {
      if (!failure.unauthorized) {
        if (failure.offline || failure.status >= 500) _mayBeGoneFor = token;
        rethrow;
      }
      if (token == null || token != _mayBeGoneFor) {
        _mayBeGoneFor = null;
        await _ref.read(sessionProvider.notifier).signOut(discardGuest: true);
        throw const AccountSessionExpired();
      }
    }
    _mayBeGoneFor = null;
    await _clearPhone(id);
  }

  Future<String?> _accountId() async {
    try {
      final profile = _ref.read(settingsProfileProvider).value;
      if (profile != null) return profile.id;
      final token = _ref.read(sessionProvider).stored?.token;
      if (token != null) return await _ref.read(authApiProvider).accountId(token);
    } on Object {
      // Offline and never read: what is kept under the id stays, and is of no use to anyone else.
    }
    return _ref.read(homeProvider).data?.userId;
  }

  /// One step at a time, each on its own: a step that cannot be done (a store that will not answer)
  /// never stops the ones after it, nor the end of the session, which is last.
  Future<void> _clearPhone(String? id) async {
    final platform = _ref.read(noticePlatformProvider);
    await _step(platform.cancelDue);
    await _step(platform.cancelGuest);
    if (id != null) {
      await _step(() => _ref.read(passkeyOfferProvider).forget(id));
      await _step(() => _ref.read(unlockHintProvider).forget(id));
      await _step(() => _ref.read(onboardingDraftStoreProvider).clear(id));
      for (final nudge in Nudge.values) {
        await _step(() => _ref.read(flagStoreProvider('home.dismissed.$id.${nudge.id}')).clear());
      }
    }
    await _step(_ref.read(modelStoreProvider).deleteModels);
    // An export shared a moment ago is a copy of everything: it goes with the account.
    await _step(_ref.read(filesChannelProvider).clearShared);
    // The home cache, the widget and the token.
    await _ref.read(sessionProvider.notifier).accountDeleted();
  }

  Future<void> _step(Future<void> Function() clear) async {
    try {
      await clear();
    } on Object {
      // See [_clearPhone].
    }
  }
}

final accountDeletionProvider = Provider<AccountDeletion>(AccountDeletion.new);
