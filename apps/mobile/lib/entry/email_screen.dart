import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import '../api/session.dart';
import '../home/home_controller.dart' show clockProvider;
import '../home/wambi_face.dart';
import '../l10n/app_localizations.dart';
import '../merge/merge_controller.dart' show mergeControllerProvider;
import '../merge/merge_offer.dart';
import '../protect/protect_actions.dart' show afterClaim, keyAfterClaimMarksProvider;
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/web_text_field.dart';
import '../vault/preview.dart' show isPreviewProvider;
import '../vault/vault_providers.dart' show vaultSessionProvider;
import 'auth_errors.dart';
import 'code_formatter.dart';
import 'code_input.dart';
import 'guest_dialogs.dart';
import 'sign_in_frame.dart';

/// "Ya tengo una cuenta" (I already have an account): the email, then the 6-digit code (the email also carries a magic link,
/// handled by VerifyLinkScreen).
///
/// On opening it also asks the phone for a passkey it can offer at once (one made on the web and
/// held by a provider such as Proton Pass): its sheet appears if there is one, and signing in with
/// it completes; with none, nothing shows and the email field is ready. "Entrar con huella" does the
/// same on demand, with the provider's own picker.
///
/// Signed out, "Sign in with my recovery key" opens the recovery-key sign-in (`/entry/recovery`).
///
/// For a signed-in guest, nothing is sent before the person decides: save their progress to the
/// email (the claim, spec section 4.2), or, after a warning, sign in as another account.
///
/// A `preview` guest (phone-first spec 7): after the claim, the recovery key with no way out until
/// it is saved, then the passkey offer (`afterClaim`); an email that has an account already offers
/// the merge (`askMerge`), whose yes holds this phone's vault (`MergeController.begin`) and sends
/// that email's code; backing out of that code calls the merge off.
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key, this.initialEmail, this.claim = false, this.passkeyLabel});

  final String? initialEmail;

  /// The passkey button's words, in place of `emailPasskey`: the web's own ("Sign in with
  /// fingerprint" in English), for the parity pictures that compare it with the web's sign-in.
  final String? passkeyLabel;

  /// Start the claim of [initialEmail] at once (a guest chose "Guardar mi progreso" elsewhere).
  final bool claim;

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

/// How long "Reenviar código" waits after a code was sent (`RESEND_DELAY_MS`, SignIn.tsx).
const resendDelay = Duration(seconds: 30);

enum _Stage { email, code }

enum _Mode { signIn, claim }

class _EmailScreenState extends ConsumerState<EmailScreen> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();

  /// A passkey prompt is open (or being asked for): no second one.
  bool _passkeyActive = false;

  _Stage _stage = _Stage.email;
  _Mode _mode = _Mode.signIn;

  /// The person was warned and chose to leave the guest account behind.
  bool _replaceGuest = false;

  /// The code step signs in to the email account a merge brings this phone's data into.
  bool _merging = false;
  bool _busy = false;

  /// Checking the code (rather than sending one).
  bool _verifying = false;
  AuthError? _error;

  /// The error is about the passkey (shown under its button), not the email field.
  bool _errorIsPasskey = false;
  bool _resent = false;

  /// When "Reenviar código" unlocks, and the clock that counts down to it once a second.
  DateTime? _resendAt;
  Timer? _ticker;

  /// The email the code went to.
  String _sentTo = '';

  @override
  void initState() {
    super.initState();
    _code.addListener(_codeChanged);
    final email = widget.initialEmail;
    if (widget.claim && email != null && emailPattern.hasMatch(normalizeEmail(email))) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claim(normalizeEmail(email)));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerPasskey());
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  void _codeChanged() {
    // The button waits for the whole code.
    if (mounted) setState(() {});
  }

  SessionController get _session => ref.read(sessionProvider.notifier);

  /// On opening: signs in with a passkey the phone can offer at once, silently when it has none.
  /// Not for a guest, whose session a passkey would replace unasked (the button warns first), nor
  /// when the screen only finishes a claim.
  Future<void> _offerPasskey() async {
    if (!mounted || _passkeyActive) return;
    setState(() => _passkeyActive = true);
    var signedIn = false;
    try {
      await _session.ready;
      if (!mounted || ref.read(sessionProvider).isGuest) return;
      if (!await ref.read(passkeysSupportedProvider.future) || !mounted) return;
      signedIn = await _session.signInWithAvailablePasskey();
    } on GuestInTheWay {
      // A guest signed in meanwhile: nothing to offer.
    } on AuthFailure catch (failure) {
      // Only a passkey the person chose and the server refused gets here.
      if (mounted) {
        setState(() {
          _error = passkeyErrorFor(failure);
          _errorIsPasskey = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = unexpectedPasskeyErrorFor(error);
          _errorIsPasskey = true;
        });
      }
    } finally {
      if (mounted) setState(() => _passkeyActive = false);
    }
    if (!mounted) return;
    if (signedIn) {
      context.go('/');
    } else if (_stage == _Stage.email) {
      // The sheet took the focus away, or never came: the email is where the person goes next.
      _emailFocus.requestFocus();
    }
  }

  /// "Entrar con huella": the phone's passkey prompt, with the provider's own picker. A guest is warned
  /// first (the passkey's account replaces theirs) and may save their progress instead.
  Future<void> _passkey() async {
    if (_passkeyActive) return;
    var replaceGuest = false;
    if (ref.read(sessionProvider).isGuest) {
      final choice = await askGuestPasskeyChoice(context);
      if (!mounted || choice == null) return;
      if (choice == GuestPasskeyChoice.save) {
        _emailFocus.requestFocus();
        return;
      }
      replaceGuest = true;
    }
    setState(() {
      _passkeyActive = true;
      _error = null;
      _errorIsPasskey = false;
      _resent = false;
    });
    var signedIn = false;
    try {
      await _session.signInWithPasskey(replaceGuest: replaceGuest);
      signedIn = true;
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _error = passkeyErrorFor(failure);
          _errorIsPasskey = true;
        });
      }
    } on GuestInTheWay {
      // A guest signed in meanwhile: the person can tap again and will be asked.
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = unexpectedPasskeyErrorFor(error);
          _errorIsPasskey = true;
        });
      }
    } finally {
      if (mounted) setState(() => _passkeyActive = false);
    }
    if (!mounted) return;
    if (signedIn) {
      context.go('/');
    } else if (_stage == _Stage.email) {
      _emailFocus.requestFocus();
    }
  }

  /// Runs [action] with the busy state on, showing a failure as [onFail] reads it.
  Future<bool> _run(Future<void> Function() action, AuthError Function(AuthFailure) onFail) async {
    setState(() {
      _busy = true;
      _error = null;
      _errorIsPasskey = false;
      _resent = false;
    });
    try {
      await action();
      return true;
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = onFail(failure));
      return false;
    } catch (error) {
      // Never an unhandled error with a busy button: a message, and the screen works again.
      if (mounted) setState(() => _error = unexpectedErrorFor(error));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final email = normalizeEmail(_email.text);
    if (!emailPattern.hasMatch(email)) {
      setState(() {
        _error = AuthError.invalidEmail;
        _errorIsPasskey = false;
      });
      return;
    }
    if (ref.read(sessionProvider).isGuest && !_replaceGuest) {
      final choice = await askGuestChoice(context, email);
      if (!mounted || choice == null) return;
      if (choice == GuestChoice.save) return _claim(email);
      if (!await confirmLeavingGuest(context, email) || !mounted) return;
      _replaceGuest = true;
    }
    await _sendSignIn(email);
  }

  Future<void> _sendSignIn(String email, {bool again = false}) async {
    final sent = await _run(
      () => _session.sendCode(email, replaceGuest: _replaceGuest),
      (failure) => authErrorFor(failure, AuthAction.send),
    );
    if (sent && mounted) _toCode(email, _Mode.signIn, again: again);
  }

  Future<void> _claim(String email, {bool again = false}) async {
    final sent = await _run(
      () => _session.claimEmail(email),
      (failure) => authErrorFor(failure, AuthAction.send),
    );
    if (!mounted) return;
    if (sent) {
      _toCode(email, _Mode.claim, again: again);
    } else if (_error == AuthError.emailTaken && _previewGuest) {
      await _offerMerge(email);
    }
  }

  /// A `preview` guest: its data lives encrypted on this phone, and its claim is followed by the
  /// recovery key and a merge offer (phone-first spec 7). A `plain` guest's flow is today's.
  bool get _previewGuest => ref.read(sessionProvider).isGuest && ref.read(isPreviewProvider);

  /// email_taken for a `preview` guest: "Bring this phone's data into it?". Yes holds this phone's
  /// vault for the merge before anything is sent, then sends the email's code (the guest's session
  /// is replaced only once the code is used); no leaves everything as it was.
  Future<void> _offerMerge(String email) async {
    if (!await askMerge(context, email) || !mounted) return;
    final merge = ref.read(mergeControllerProvider.notifier);
    var begun = false;
    final sent = await _run(() async {
      await merge.begin(email);
      begun = true;
      await _session.sendCode(email, replaceGuest: true);
    }, (failure) => authErrorFor(failure, AuthAction.send));
    if (!sent) {
      // No code went out: the merge never started for the person, so its hold goes.
      if (begun) await _cancelMerge();
      return;
    }
    if (!mounted) return;
    _merging = true;
    _replaceGuest = true;
    _toCode(email, _Mode.signIn, again: false);
  }

  /// Calls a begun merge off (before its sign-in only the hold goes): without it the hold would
  /// keep this phone's vault, and the merge would wait, for good.
  Future<void> _cancelMerge() async {
    _merging = false;
    try {
      await ref.read(mergeControllerProvider.notifier).cancel();
    } on Object catch (error) {
      // The hold stays (the next start's resume picks the merge up again, waiting for the email's
      // sign-in; only a cancel or a later begin clears it): the person is told it did not go.
      if (mounted) {
        setState(() {
          _error = unexpectedErrorFor(error);
          _errorIsPasskey = false;
        });
      }
    }
  }

  /// After email_taken: that email has its own account; signing in to it leaves the guest behind.
  /// A `preview` guest is offered the merge instead, which brings this phone's data along.
  Future<void> _signInInstead() async {
    final email = normalizeEmail(_email.text);
    if (_previewGuest) return _offerMerge(email);
    if (!await confirmLeavingGuest(context, email) || !mounted) return;
    _replaceGuest = true;
    await _sendSignIn(email);
  }

  /// The seconds until "Reenviar código" unlocks (the web's `useSecondsUntil`), 0 when it has.
  int get _resendIn {
    final at = _resendAt;
    if (at == null) return 0;
    final left = at.difference(ref.read(clockProvider)()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  void _startResendWait() {
    _resendAt = ref.read(clockProvider)().add(resendDelay);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_resendIn == 0) _ticker?.cancel();
    });
  }

  void _toCode(String email, _Mode mode, {required bool again}) {
    _startResendWait();
    setState(() {
      _sentTo = email;
      _mode = mode;
      _stage = _Stage.code;
      _resent = again;
      _code.clear();
    });
  }

  Future<void> _submitCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _verifying = true);
    final claim = _mode == _Mode.claim;
    // A `preview` guest's claim goes on here after the email is set: the router keeps this screen
    // while its recovery key and passkey offer come (`claimFinishingProvider`).
    final finishing = claim && _previewGuest;
    final claimFinishing = ref.read(claimFinishingProvider.notifier);
    final keepCapturesOf = _merging ? ref.read(mergeControllerProvider.notifier).guestUserId : null;
    // The recovery key this claim asks for is owed from now on, so a process killed on its page
    // shows it again when the vault next opens (`KeyAfterClaimMarks`).
    final userId = ref.read(vaultSessionProvider)?.userId;
    if (finishing && userId != null) {
      try {
        await ref.read(keyAfterClaimMarksProvider).owe(userId);
      } on Object {
        // The claim's own key page still comes; only a kill on it would not bring it back.
      }
      if (!mounted) return;
    }
    if (finishing) claimFinishing.finishing = true;
    try {
      final ok = await _run(
        () => claim
            ? _session.confirmClaim(_sentTo, code)
            : _session.verifyCode(
                _sentTo,
                code,
                replaceGuest: _replaceGuest,
                keepCapturesOf: keepCapturesOf,
              ),
        (failure) {
          final error = authErrorFor(failure, AuthAction.signIn);
          if (isCodeError(error)) _code.clear();
          return error;
        },
      );
      if (!mounted) return;
      setState(() => _verifying = false);
      if (!ok) return;
      // Signed in to the merge's account: the merge goes on from its open vault (lib/merge).
      _merging = false;
      if (finishing) {
        await afterClaim(context, ref);
        claimFinishing.finishing = false;
        if (!mounted) return;
      }
      context.go('/');
    } finally {
      if (finishing) claimFinishing.finishing = false;
    }
  }

  void _resend() =>
      _mode == _Mode.claim ? _claim(_sentTo, again: true) : _sendSignIn(_sentTo, again: true);

  void _changeEmail() {
    setState(() {
      // A new email gets its own question (and warning) for a guest.
      _replaceGuest = false;
      _stage = _Stage.email;
      _error = null;
      _errorIsPasskey = false;
      _resent = false;
    });
    // Out of a merge's code: the merge is called off, and the guest stays as it was.
    if (_merging) unawaited(_cancelMerge());
  }

  /// The web's `w-full`.
  Widget _full(Widget child) => SizedBox(width: double.infinity, child: child);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      // Back from the code goes to the email, as "Usar otro correo" does; from the email it leaves.
      canPop: _stage == _Stage.email,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stage == _Stage.code) _changeEmail();
      },
      child: SignInFrame(
        mood: WambiMood.happy,
        children: _stage == _Stage.email ? _emailStage(l10n) : _codeStage(l10n),
      ),
    );
  }

  /// The email step (`SignIn`'s `email` step): the title and lead, "Entrar con huella" first when the
  /// phone has passkeys, then the email and "Enviar código".
  List<Widget> _emailStage(AppLocalizations l10n) {
    final error = _error;
    final passkeys = ref.watch(passkeysSupportedProvider).value ?? false;
    final passkeyError = _errorIsPasskey;
    return [
      EntryTitle(l10n.signInTitle),
      EntryLead(l10n.signInLead),
      if (passkeys) ...[
        _full(
          PressButton(
            key: const Key('entry.passkey'),
            tone: PressTone.secondary,
            onPressed: _busy || _passkeyActive ? null : _passkey,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: WambitoTokens.space2,
              children: [
                const FingerprintIcon(),
                Flexible(
                  child: Text(
                    (_passkeyActive
                            ? l10n.emailPasskeyBusy
                            : (widget.passkeyLabel ?? l10n.emailPasskey))
                        .toUpperCase(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (passkeyError && error != null) FieldError(error.message(l10n)),
        OrDivider(l10n.signInOrEmail),
      ],
      _full(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space3,
          children: [
            FieldCaption(l10n.emailLabel),
            WebTextField(
              fieldKey: const Key('entry.email'),
              controller: _email,
              focusNode: _emailFocus,
              label: l10n.emailLabel,
              placeholder: l10n.emailPlaceholder,
              invalid: error != null && !passkeyError,
              readOnly: _busy,
              autofocus: widget.initialEmail == null,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
            if (error != null && !passkeyError) FieldError(error.message(l10n)),
            if (error == AuthError.emailTaken && !passkeyError)
              PressButton.text(
                l10n.emailTakenSignIn,
                tone: PressTone.secondary,
                onPressed: _busy ? null : _signInInstead,
              ),
            PressButton.text(
              _busy ? l10n.sending : l10n.sendCode,
              key: const Key('entry.send'),
              onPressed: _busy ? null : _send,
            ),
          ],
        ),
      ),
      EntryNote(l10n.signInFirstTime),
      // Signed out only: a guest's session would be replaced (the route is signed-out only too).
      if (ref.watch(sessionProvider).status == SessionStatus.signedOut)
        _full(
          PressButton.text(
            l10n.entryUseRecoveryKey,
            key: const Key('entry.useRecoveryKey'),
            tone: PressTone.ghost,
            link: true,
            onPressed: _busy || _passkeyActive ? null : () => context.push('/entry/recovery'),
          ),
        ),
    ];
  }

  /// The code step: the boxes, "Entrar" (or "Guardar" for a guest's claim), and the two ways back.
  List<Widget> _codeStage(AppLocalizations l10n) {
    final error = _error;
    final claim = _mode == _Mode.claim;
    final complete = _code.text.length == codeLength;
    final resendIn = _resendIn;
    final text = claim ? l10n.claimCodeLead(_sentTo) : l10n.codeLead(_sentTo);
    return [
      EntryTitle(l10n.codeTitle),
      EntryLead(text, strong: _sentTo),
      _full(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space3,
          children: [
            CodeInput(
              fieldKey: const Key('entry.code'),
              controller: _code,
              focusNode: _codeFocus,
              label: l10n.codeLabel,
              invalid: error != null && isCodeError(error),
              readOnly: _busy,
              autofocus: true,
              onSubmitted: (_) {
                if (!_busy && _code.text.length == codeLength) _submitCode();
              },
            ),
            if (error != null) FieldError(error.message(l10n)),
            if (_resent && error == null) _Resent(l10n.resent),
            PressButton.text(
              _verifying ? l10n.verifying : (claim ? l10n.submitClaim : l10n.submitCode),
              key: const Key('entry.submitCode'),
              onPressed: _busy || !complete ? null : _submitCode,
            ),
          ],
        ),
      ),
      // Stacked: nothing here changes width and reflows the row.
      Column(
        children: [
          PressButton.text(
            resendIn > 0 ? l10n.resendIn(resendIn) : l10n.resend,
            tone: PressTone.ghost,
            onPressed: _busy || resendIn > 0 ? null : _resend,
          ),
          PressButton.text(
            l10n.changeEmail,
            tone: PressTone.ghost,
            onPressed: _busy ? null : _changeEmail,
          ),
        ],
      ),
    ];
  }
}

/// "Te mandamos un código nuevo.", read out politely when it appears.
class _Resent extends StatelessWidget {
  const _Resent(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    container: true,
    child: Text(text, style: LkText.note.copyWith(color: context.lkColors.ink)),
  );
}
