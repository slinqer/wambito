// The merge's question (phone-first spec 7.2): the email a guest claims already has an account.
// It says, before the sign-in (step 2), that this phone's recovery key stops working.
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/confirm_sheet.dart';
import '../ui/press_button.dart';

/// "This email already has a Wambito account. Bring this phone's data into it?": true for yes
/// (`merge.yes`); false when the person backs out (Cancel, the backdrop, Escape).
Future<bool> askMerge(BuildContext context, String email) async {
  final l10n = AppLocalizations.of(context);
  final yes = await ChoiceSheet.show<bool>(
    context,
    title: l10n.mergeOfferQuestion,
    body: l10n.mergeOfferBody(email),
    note: l10n.mergeOfferKeyNote,
    choices: [
      SheetChoice(
        key: const Key('merge.yes'),
        label: l10n.mergeOfferYes,
        value: true,
        tone: PressTone.primary,
      ),
    ],
  );
  return yes ?? false;
}
