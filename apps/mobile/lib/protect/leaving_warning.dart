// The warning before a `preview` guest with no way back leaves (phone-first spec 5.2, ruling 22):
// signing out or changing server deletes the data from this phone, and with neither a recovery key
// nor a passkey nobody can open the copy on the server. A guest with a way back is not warned
// (beyond the unsynced-changes sheet); a `plain` guest keeps `warnGuestLeaving`.
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../progress/guest_warning.dart' show GuestLeaving;
import '../ui/confirm_sheet.dart';
import '../ui/press_button.dart';

/// What the person chose: make a way back first, or leave anyway.
enum UnprotectedChoice { protectFirst, leave }

/// The sheet. [passkeyUnknown] says the passkey wraps could not be read (offline): the recovery key
/// is known to be missing, but a passkey may exist, so a note says that instead of claiming none.
/// Null: the person backed out.
Future<UnprotectedChoice?> warnUnprotectedLeaving(
  BuildContext context,
  GuestLeaving leaving, {
  bool passkeyUnknown = false,
}) {
  final l10n = AppLocalizations.of(context);
  final (title, body, confirm, confirmKey) = switch (leaving) {
    GuestLeaving.signOut => (
      l10n.unprotectedSignOutTitle,
      l10n.unprotectedSignOutBody,
      l10n.guestSignOutConfirm,
      'unprotected.signOutConfirm',
    ),
    GuestLeaving.changeServer => (
      l10n.unprotectedServerTitle,
      l10n.unprotectedServerBody,
      l10n.guestServerConfirm,
      'unprotected.serverConfirm',
    ),
  };
  return ChoiceSheet.show<UnprotectedChoice>(
    context,
    title: title,
    body: body,
    note: passkeyUnknown ? l10n.unprotectedPasskeyUnknown : null,
    choices: [
      SheetChoice(
        key: const Key('unprotected.protectFirst'),
        label: l10n.unprotectedProtectFirst,
        value: UnprotectedChoice.protectFirst,
        tone: PressTone.primary,
      ),
      SheetChoice(
        key: Key(confirmKey),
        label: confirm,
        value: UnprotectedChoice.leave,
        danger: true,
      ),
    ],
  );
}
