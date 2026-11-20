// The passkey offer's page: the screen wired to the session (`/entry/passkey-offer`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import '../api/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/toast.dart';
import '../protect/protect_actions.dart' show protectWithPasskey;
import '../settings/passkeys_settings.dart' show PasskeyOutcome;
import '../settings/security/security_api.dart' show securityApiProvider;
import '../vault/preview.dart' show isPreviewProvider;
import 'passkey_offer_screen.dart';

/// What adding the passkey came to, from the failure Better Auth or the phone gave: closing the
/// phone's prompt is no failure (`cancelled`), and a passkey this phone already has counts as made.
PasskeyOfferOutcome passkeyOfferOutcome(AuthFailure failure) => switch (failure.code) {
  'AUTH_CANCELLED' ||
  'ERROR_CEREMONY_ABORTED' ||
  'ERROR_PASSTHROUGH_SEE_CAUSE_PROPERTY' => PasskeyOfferOutcome.cancelled,
  'ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED' => PasskeyOfferOutcome.added,
  _ => PasskeyOfferOutcome.failed,
};

/// `/entry/passkey-offer`: the offer, wired to the session. Making the passkey is the existing
/// `registerPasskey()`; either answer is kept for the account and leads on to home, with the
/// confirmation when a passkey was made.
///
/// A `preview` account whose vault is open (the offer after a claim, lib/protect/protect_actions.dart
/// `afterClaim`) makes it as "Protect your data"'s step 2 (`protectWithPasskey`), so its PRF wraps
/// the data key; a password manager that gives no PRF still adds a passkey that only signs in, and
/// the offer then says `settingsPasskeysAddNoPrf` in text that stays, with "Seguir"; a PRF whose
/// wrap could not be saved still ends with the toast "This passkey can sign you in but cannot open
/// your data. Add a recovery key."
class PasskeyOfferPage extends ConsumerWidget {
  const PasskeyOfferPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(sessionProvider.notifier);
    // Whether the passkey made here opens the data too (always for a `plain` account, which has
    // nothing encrypted to open).
    var opensData = true;
    // The passkey itself gave no PRF: the offer said so already, as text that stays.
    var noPrfSaid = false;
    return PasskeyOfferScreen(
      add: () async {
        if (ref.read(isPreviewProvider) && ref.read(securityApiProvider) != null) {
          opensData = false;
          var withoutPrf = false;
          final outcome = await protectWithPasskey(
            context,
            ref,
            onPrfKept: () => opensData = true,
            onNoPrf: () => withoutPrf = true,
          );
          noPrfSaid = withoutPrf;
          return switch (outcome) {
            PasskeyOutcome.added when withoutPrf => PasskeyOfferOutcome.addedWithoutPrf,
            PasskeyOutcome.added => PasskeyOfferOutcome.added,
            PasskeyOutcome.cancelled => PasskeyOfferOutcome.cancelled,
            PasskeyOutcome.failed => PasskeyOfferOutcome.failed,
          };
        }
        try {
          await session.registerPasskey();
          return PasskeyOfferOutcome.added;
        } on AuthFailure catch (failure) {
          return passkeyOfferOutcome(failure);
        }
      },
      onAnswered: (added) async {
        final router = GoRouter.of(context);
        final toasts = ToastHost.of(context);
        final l10n = AppLocalizations.of(context);
        await session.answerPasskeyOffer();
        // A PRF whose wrap could not be saved keeps today's message; one that gave none was said.
        if (added && !noPrfSaid) {
          toasts.say(opensData ? l10n.passkeyOfferAdded : l10n.protectPasskeyNoPrf);
        }
        router.go('/');
      },
    );
  }
}
