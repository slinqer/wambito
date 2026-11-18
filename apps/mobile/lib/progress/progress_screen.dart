import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import '../api/session.dart';
import '../entry/auth_errors.dart';
import '../entry/sign_in_frame.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/web_text_field.dart';
import '../vault/preview.dart' show isPreviewProvider;

/// "Guarda tu progreso" (spec section 6.1.5, guests only): says honestly what a guest account is,
/// and offers the two ways to keep it. The email claim (section 4.2) is the real one: the guest's
/// own user receives the email, so every movement stays. A passkey (section 4.3) lets the guest
/// back in on this phone, but loses the account with the phone, and sync, AI and MCP need an email.
///
/// A `preview` guest (phone-first ruling 20) sees what an email adds instead: its data is already
/// encrypted on the server, and an email alone opens none of it, so neither "without an email you
/// lose your data" nor the passkey section (that is "Protect your data"'s step 2, offered after the
/// claim) is said here.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

enum _Passkey { idle, busy, added }

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  final _email = TextEditingController();
  final _emailFocus = FocusNode();
  AuthError? _emailError;

  _Passkey _passkey = _Passkey.idle;
  String? _passkeyError;

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  /// Hands the claim to the email screen, which sends the code, takes it, and says what went
  /// wrong (an email on the allowlist's other side, one that has an account already...).
  void _save() {
    final email = normalizeEmail(_email.text);
    if (!emailPattern.hasMatch(email)) {
      setState(() => _emailError = AuthError.invalidEmail);
      return;
    }
    setState(() => _emailError = null);
    context.push(
      Uri(path: '/entry/email', queryParameters: {'email': email, 'claim': '1'}).toString(),
    );
  }

  Future<void> _addPasskey() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _passkey = _Passkey.busy;
      _passkeyError = null;
    });
    String? error;
    var added = false;
    try {
      await ref.read(sessionProvider.notifier).registerPasskey();
      added = true;
    } on AuthFailure catch (failure) {
      // Closing the phone's prompt needs no explaining.
      if (failure.code != 'AUTH_CANCELLED') {
        final reason = authErrorFor(failure, AuthAction.signIn);
        error = retryableErrors.contains(reason)
            ? reason.message(l10n)
            : l10n.progressPasskeyFailed;
      }
    } catch (failure) {
      final reason = unexpectedErrorFor(failure);
      error = reason == AuthError.networkError ? reason.message(l10n) : l10n.progressPasskeyFailed;
    }
    if (!mounted) return;
    setState(() {
      _passkey = added ? _Passkey.added : _Passkey.idle;
      _passkeyError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final preview = ref.watch(isPreviewProvider);
    final passkeys = !preview && (ref.watch(passkeysSupportedProvider).value ?? false);
    final error = _emailError;
    // The web's sign-in language: the frame, the title, a lead, a form, the line between two ways.
    return SignInFrame(
      children: [
        if (preview) ...[
          EntryTitle(l10n.protectEmailTitle),
          // What the email adds, then that the data stays as it is and the key comes next.
          EntryLead(l10n.protectEmailLead, ink: true),
          EntryLead(l10n.progressPreviewBody),
        ] else ...[
          EntryTitle(l10n.progressTitle),
          // What a guest account is, said plainly, then what saving to an email does.
          EntryLead(l10n.progressLead, ink: true),
          EntryLead(l10n.progressEmailBody),
        ],
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space3,
            children: [
              FieldCaption(l10n.emailLabel),
              WebTextField(
                fieldKey: const Key('progress.email'),
                controller: _email,
                focusNode: _emailFocus,
                label: l10n.emailLabel,
                placeholder: l10n.emailPlaceholder,
                invalid: error != null,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _save(),
              ),
              if (error != null) FieldError(error.message(l10n)),
              PressButton.text(
                l10n.progressSave,
                key: const Key('progress.save'),
                onPressed: _save,
              ),
            ],
          ),
        ),
        if (passkeys) ...[
          OrDivider(l10n.progressPasskeyTitle),
          EntryLead(l10n.progressPasskeyBody),
          if (_passkey == _Passkey.added)
            Semantics(
              liveRegion: true,
              container: true,
              child: Text(
                l10n.progressPasskeyAdded,
                textAlign: TextAlign.center,
                style: LkText.copy.copyWith(color: colors.good),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: PressButton(
                key: const Key('progress.passkey'),
                tone: PressTone.secondary,
                onPressed: _passkey == _Passkey.busy ? null : _addPasskey,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: WambitoTokens.space2,
                  children: [
                    const FingerprintIcon(),
                    Flexible(
                      child: Text(
                        (_passkey == _Passkey.busy
                                ? l10n.progressPasskeyAdding
                                : l10n.progressPasskeyAdd)
                            .toUpperCase(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_passkeyError != null) FieldError(_passkeyError!),
        ],
      ],
    );
  }
}
