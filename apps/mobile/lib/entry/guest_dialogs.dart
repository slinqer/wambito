import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/confirm_sheet.dart';
import '../ui/press_button.dart';

// What the entry screens ask of a guest who is about to sign in. They are the web's sheet
// (`ConfirmSheet`, apps/web/app/ui/ConfirmSheet.tsx) with the choices a guest has: the web has no
// guests, so it has no such question.

/// What a guest who typed an email chose to do with it.
enum GuestChoice { save, otherAccount }

/// Asked when a guest enters with an email (spec section 4.2): save their progress to that email
/// (the claim: same account, every movement kept), or sign in as another account. Null: neither.
Future<GuestChoice?> askGuestChoice(BuildContext context, String email) {
  final l10n = AppLocalizations.of(context);
  return ChoiceSheet.show<GuestChoice>(
    context,
    title: l10n.guestSaveTitle,
    body: l10n.guestSaveBody(email),
    choices: [
      SheetChoice(
        key: const Key('guest.save'),
        label: l10n.guestSaveAction,
        value: GuestChoice.save,
        tone: PressTone.primary,
      ),
      SheetChoice(
        key: const Key('guest.otherAccount'),
        label: l10n.guestOtherAccount,
        value: GuestChoice.otherAccount,
      ),
    ],
  );
}

/// The warning before a guest's session is replaced by [email]'s: the guest's account has no email,
/// so once its token is gone nobody can reach it again. True only when the person confirms.
Future<bool> confirmLeavingGuest(BuildContext context, String email) {
  final l10n = AppLocalizations.of(context);
  return ConfirmSheet.show(
    context,
    title: l10n.guestLeaveTitle,
    body: l10n.guestLeaveBody(email),
    confirmLabel: l10n.guestLeaveConfirm,
    confirmKey: const Key('guest.leaveConfirm'),
    onConfirm: () async {},
  );
}

/// What a guest who chose "Entrar con huella" decided.
enum GuestPasskeyChoice { save, signIn }

/// The warning before a guest signs in with a passkey (spec section 4.2), which replaces the
/// guest's session: its email is not known, so the warning cannot name one. The person may instead
/// save their progress to an email first (the claim). Null: neither.
Future<GuestPasskeyChoice?> askGuestPasskeyChoice(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return ChoiceSheet.show<GuestPasskeyChoice>(
    context,
    title: l10n.guestLeaveTitle,
    body: l10n.guestPasskeyBody,
    choices: [
      SheetChoice(
        key: const Key('guest.save'),
        label: l10n.guestSaveAction,
        value: GuestPasskeyChoice.save,
        tone: PressTone.primary,
      ),
      SheetChoice(
        key: const Key('guest.leaveConfirm'),
        label: l10n.guestLeaveConfirm,
        value: GuestPasskeyChoice.signIn,
        danger: true,
      ),
    ],
  );
}
