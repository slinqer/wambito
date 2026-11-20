import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import '../api/session.dart';
import '../home/wambi_face.dart';
import '../l10n/app_localizations.dart';
import '../theme/tokens.g.dart';
import '../ui/press_button.dart';
import '../vault/recovery_key_input.dart';
import 'auth_errors.dart';
import 'sign_in_frame.dart';

/// "Sign in with my recovery key" (the email screen's link, `/entry/recovery`, signed out only): the
/// recovery key signs in (`POST /v2/recovery/sign-in`), and the same typed key then opens the
/// account's data without being asked again (the session holds its parsed bytes for the vault gate,
/// ruling 6). The text is read as Unlock reads it: any case, spaces, dashes, O for 0. The field is
/// Unlock's (`RecoveryKeyField`): grouped while typed, "Paste" in it, submit once the key is full.
///
/// A key that signs in nothing gets one message whatever the reason (the server does not say why, and
/// a `plain` account has no verifier); too many tries say how long to wait.
class RecoverySignInScreen extends ConsumerStatefulWidget {
  const RecoverySignInScreen({super.key});

  @override
  ConsumerState<RecoverySignInScreen> createState() => _RecoverySignInScreenState();
}

class _RecoverySignInScreenState extends ConsumerState<RecoverySignInScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _busy = false;

  /// The message under the field, already in words.
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A full key enables it; the parser stays the judge of what is typed.
  bool get _canSubmit => !_busy && isFullRecoveryKey(_text.text);

  /// The words for a failed sign-in: a 429 says the minutes the server asked to wait.
  String _messageFor(AuthFailure failure, AppLocalizations l10n) {
    final wait = failure.retryAfter;
    if (failure.status == 429 && wait != null) {
      return l10n.recoverySignInWait((wait / 60).ceil());
    }
    return authErrorFor(failure, AuthAction.signIn).message(l10n);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    var signedIn = false;
    try {
      await ref.read(sessionProvider.notifier).signInWithRecoveryKey(_text.text);
      signedIn = true;
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _messageFor(failure, l10n));
    } catch (error) {
      // Never an unhandled error with a busy button: a message, and the screen works again.
      if (mounted) setState(() => _error = unexpectedErrorFor(error).message(l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!signedIn || !mounted) return;
    // The key is held as bytes for the vault now; the text goes.
    _text.clear();
    context.go('/');
  }

  void _useEmail() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/entry/email');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _error;
    return SignInFrame(
      mood: WambiMood.happy,
      children: [
        EntryTitle(l10n.recoverySignInTitle),
        EntryLead(l10n.recoverySignInLead),
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space3,
            children: [
              FieldCaption(l10n.vaultUnlockLabel),
              RecoveryKeyField(
                fieldKey: const Key('recovery.input'),
                pasteKey: const Key('recovery.paste'),
                controller: _text,
                focusNode: _focus,
                invalid: error != null,
                readOnly: _busy,
                autofocus: true,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => unawaited(_submit()),
              ),
              if (error != null) FieldError(error),
              PressButton.text(
                _busy ? l10n.recoverySignInBusy : l10n.recoverySignInSubmit,
                key: const Key('recovery.submit'),
                onPressed: _canSubmit ? () => unawaited(_submit()) : null,
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: PressButton.text(
            l10n.recoverySignInUseEmail,
            key: const Key('recovery.useEmail'),
            tone: PressTone.ghost,
            link: true,
            onPressed: _busy ? null : _useEmail,
          ),
        ),
      ],
    );
  }
}
