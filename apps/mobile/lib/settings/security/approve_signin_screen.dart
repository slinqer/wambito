// Approving a web sign-in from this phone (phone-first spec 8.1 steps 2-6): the web shows a QR and
// a code; the person scans the QR (the phone's own camera, `wambito/scanner` asked for
// `wambito://signin?` only) or types the code, sees "Sign in on **{label}**?" with the warning
// "Only scan a code you see on **{host}**" (the host of the server this phone talks to), and
// approves or cancels. After a typed code both screens show the same 6-digit number and "They
// match" seals the data key; after a QR the key in it already authenticates the browser, so
// Approve seals at once. Cancel before Approve posts nothing.
//
// The request holds an ephemeral private key until it ends, so whenever the screen goes away
// before it is done (back, Cancel, "They do not match", a failure) the request is cancelled. It
// needs the vault open (`securityApiProvider`); a `plain` account or a locked vault has none and
// the screen only says so.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/server_url.dart';
import '../../entry/sign_in_frame.dart';
import '../../home/wambi_face.dart';
import '../../l10n/app_localizations.dart';
import '../../local/signin_approval.dart' show SigninApproval;
import '../../scanner/qr_scanner.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.g.dart';
import '../../ui/lk_theme.dart';
import '../../ui/press_button.dart';
import '../../ui/web_text_field.dart';
import '../../vault/pair_new_device_view.dart' show PairingProblem;
import 'approve_device_screen.dart' show UpperCaseFormatter;
import 'security_api.dart';

sealed class _View {
  const _View();
}

class _Enter extends _View {
  const _Enter({this.badCode = false, this.cameraFailed = false, this.busy = false});

  final bool badCode;
  final bool cameraFailed;
  final bool busy;
}

class _Ask extends _View {
  const _Ask(this.approval, {this.approving = false});

  final SigninApproval approval;
  final bool approving;
}

class _Number extends _View {
  const _Number(this.approval, this.number, {this.sealing = false});

  final SigninApproval approval;
  final String number;
  final bool sealing;
}

class _Sealing extends _View {
  const _Sealing();
}

class _Done extends _View {
  const _Done(this.label);

  final String label;
}

class _Mismatch extends _View {
  const _Mismatch();
}

class _Failed extends _View {
  const _Failed(this.problem);

  final PairingProblem problem;
}

const _mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Roboto Mono', 'Courier'],
  fontWeight: FontWeight.w700,
);

/// A thrown error as a problem to show; null for a cancel (nothing to say) and for `bad_code`
/// (the field's). Anything that is not the relay's (a [KeysError] of the vault) is `server`.
PairingProblem? _problemOf(Object error) => switch (codeOf(error)) {
  'cancelled' || 'bad_code' => null,
  'expired' => PairingProblem.expired,
  'tampered' => PairingProblem.tampered,
  'offline' => PairingProblem.offline,
  _ => PairingProblem.server,
};

class ApproveSigninScreen extends ConsumerStatefulWidget {
  const ApproveSigninScreen({super.key, this.qr, this.onDone});

  /// A scanned QR to look up at once (a `wambito://signin?…` link the system camera opened).
  final String? qr;

  /// Closes the screen; by default it pops its route.
  final VoidCallback? onDone;

  @override
  ConsumerState<ApproveSigninScreen> createState() => _ApproveSigninScreenState();
}

class _ApproveSigninScreenState extends ConsumerState<ApproveSigninScreen> {
  _View _view = const _Enter();
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _canScan = false;

  /// The request in progress, cancelled when the screen goes away before it is done.
  SigninApproval? _current;

  @override
  void initState() {
    super.initState();
    unawaited(_checkScanner());
    final qr = widget.qr;
    if (qr != null) {
      _view = const _Enter(busy: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_find(qr: qr));
      });
    }
  }

  Future<void> _checkScanner() async {
    bool available;
    try {
      available = await ref.read(qrScannerProvider).isAvailable();
    } on Object {
      available = false;
    }
    if (mounted && available) setState(() => _canScan = true);
  }

  @override
  void dispose() {
    _release();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Lets go of the request in progress (its ephemeral private key); safe to call twice.
  void _release() {
    final current = _current;
    _current = null;
    current?.cancel();
  }

  void _close() {
    _release();
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _fail(SigninApproval? from, Object error) {
    if (from != null && _current != from) return;
    final problem = _problemOf(error);
    if (problem == null) {
      if (codeOf(error) == 'bad_code') setState(() => _view = const _Enter(badCode: true));
      return;
    }
    _release();
    setState(() => _view = _Failed(problem));
  }

  Future<void> _find({String? code, String? qr}) async {
    final security = ref.read(securityApiProvider);
    if (security == null) return;
    setState(() => _view = const _Enter(busy: true));
    final SigninApproval found;
    try {
      found = await security.findSigninRequest(code: code, qr: qr);
    } on Object catch (error) {
      if (mounted) _fail(null, error);
      return;
    }
    if (!mounted) {
      found.cancel();
      return;
    }
    _current = found;
    setState(() => _view = _Ask(found));
  }

  Future<void> _scan() async {
    setState(() => _view = const _Enter(busy: true));
    final String? text;
    try {
      text = await ref.read(qrScannerProvider).scan(prefixes: const [signinQrPrefix]);
    } on Object {
      if (mounted) setState(() => _view = const _Enter(cameraFailed: true));
      return;
    }
    if (!mounted) return;
    // Closed, or no camera permission: back to the field, with nothing said.
    if (text == null) {
      setState(() => _view = const _Enter());
      return;
    }
    await _find(qr: text);
  }

  Future<void> _approve(SigninApproval approval) async {
    setState(() => _view = _Ask(approval, approving: true));
    final String? number;
    try {
      number = await approval.approve();
    } on Object catch (error) {
      if (mounted) _fail(approval, error);
      return;
    }
    if (!mounted || _current != approval) return;
    final shown = number;
    if (shown != null) {
      setState(() => _view = _Number(approval, shown));
      return;
    }
    await _seal(approval);
  }

  Future<void> _seal(SigninApproval approval) async {
    final view = _view;
    setState(
      () => _view = view is _Number
          ? _Number(approval, view.number, sealing: true)
          : const _Sealing(),
    );
    try {
      await approval.seal();
    } on Object catch (error) {
      if (mounted) _fail(approval, error);
      return;
    }
    if (!mounted || _current != approval) return;
    _current = null;
    setState(() => _view = _Done(approval.label));
  }

  void _startAgain() {
    _code.clear();
    setState(() => _view = const _Enter());
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Back before the approval is done: the ephemeral key goes now, not when the route is disposed.
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _release();
    },
    child: Scaffold(body: _body(context)),
  );

  Widget _full(Widget child) => SizedBox(width: double.infinity, child: child);

  Widget _closeButton(AppLocalizations l10n, {PressTone tone = PressTone.primary}) => _full(
    PressButton.text(
      l10n.vaultApproveClose,
      key: const Key('signin.close'),
      tone: tone,
      onPressed: _close,
    ),
  );

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final view = _view;

    if (ref.watch(securityApiProvider) == null && view is! _Done) {
      return SignInFrame(
        mood: WambiMood.worried,
        children: [
          EntryTitle(l10n.signinApproveTitle),
          EntryLead(l10n.signinApproveLocked),
          _closeButton(l10n),
        ],
      );
    }

    if (view is _Done || view is _Mismatch) {
      return SignInFrame(
        mood: view is _Done ? WambiMood.celebrating : WambiMood.worried,
        children: [
          if (view is _Done) ...[
            EntryTitle(l10n.vaultApproveDoneTitle),
            EntryLead(l10n.signinApproveDoneLead(view.label), strong: view.label),
          ] else ...[
            EntryTitle(l10n.vaultApproveMismatchTitle),
            EntryLead(l10n.signinApproveMismatchLead),
          ],
          _closeButton(l10n),
        ],
      );
    }

    if (view is _Failed) {
      final problem = view.problem;
      final expired = problem == PairingProblem.expired;
      final tampered = problem == PairingProblem.tampered;
      return SignInFrame(
        mood: WambiMood.worried,
        children: [
          EntryTitle(expired ? l10n.vaultApproveExpiredTitle : l10n.signinApproveFailedTitle),
          if (expired)
            EntryLead(l10n.signinApproveExpiredLead)
          else
            FieldError(switch (problem) {
              PairingProblem.tampered => l10n.vaultApproveTampered,
              PairingProblem.offline => l10n.vaultApproveOffline,
              _ => l10n.vaultApproveServer,
            }),
          if (!tampered)
            _full(
              PressButton.text(
                l10n.vaultApproveRestart,
                key: const Key('signin.restart'),
                onPressed: _startAgain,
              ),
            ),
          _closeButton(l10n, tone: tampered ? PressTone.primary : PressTone.ghost),
        ],
      );
    }

    if (view is _Sealing) {
      return SignInFrame(
        children: [
          EntryTitle(l10n.signinApproveTitle),
          Semantics(liveRegion: true, container: true, child: EntryLead(l10n.signinApproveSealing)),
        ],
      );
    }

    if (view is _Number) {
      return SignInFrame(
        children: [
          EntryTitle(l10n.signinApproveTitle),
          Semantics(
            header: true,
            child: Text(
              l10n.vaultApproveNumberTitle,
              textAlign: TextAlign.center,
              style: LkText.title.copyWith(color: colors.ink, fontSize: 18),
            ),
          ),
          Text(
            '${view.number.substring(0, 3)} ${view.number.substring(3)}',
            key: const Key('signin.number'),
            style: _mono.copyWith(fontSize: 40, height: 1, letterSpacing: 4.8, color: colors.ink),
          ),
          EntryLead(l10n.signinApproveNumberLead),
          _full(
            PressButton.text(
              view.sealing ? l10n.signinApproveSealing : l10n.vaultApproveMatch,
              key: const Key('signin.match'),
              onPressed: view.sealing ? null : () => unawaited(_seal(view.approval)),
            ),
          ),
          _full(
            PressButton.text(
              l10n.vaultApproveNoMatch,
              key: const Key('signin.noMatch'),
              tone: PressTone.secondary,
              onPressed: view.sealing
                  ? null
                  : () {
                      _release();
                      setState(() => _view = const _Mismatch());
                    },
            ),
          ),
        ],
      );
    }

    if (view is _Ask) {
      final label = view.approval.label;
      final host = ref.watch(serverUrlProvider).host;
      return SignInFrame(
        children: [
          EntryTitle(l10n.signinApproveTitle),
          EntryLead(l10n.signinApproveQuestion(label), strong: label, ink: true),
          EntryLead(l10n.signinApproveWarning(host), strong: host),
          if (view.approving)
            Semantics(
              liveRegion: true,
              container: true,
              child: EntryLead(l10n.signinApproveWaiting),
            ),
          _full(
            PressButton.text(
              l10n.signinApproveApprove,
              key: const Key('signin.approve'),
              onPressed: view.approving ? null : () => unawaited(_approve(view.approval)),
            ),
          ),
          _full(
            PressButton.text(
              l10n.vaultApproveCancel,
              key: const Key('signin.cancel'),
              tone: PressTone.ghost,
              onPressed: _close,
            ),
          ),
        ],
      );
    }

    final enter = view as _Enter;
    final busy = enter.busy;
    return SignInFrame(
      children: [
        EntryTitle(l10n.signinApproveTitle),
        EntryLead(l10n.signinApproveLead),
        if (_canScan)
          Column(
            spacing: WambitoTokens.space2,
            children: [
              _full(
                PressButton.text(
                  l10n.vaultApproveScan,
                  key: const Key('signin.scan'),
                  tone: PressTone.secondary,
                  onPressed: busy ? null : () => unawaited(_scan()),
                ),
              ),
              if (enter.cameraFailed) FieldError(l10n.vaultApproveCameraFailed),
            ],
          ),
        _full(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space3,
            children: [
              FieldCaption(l10n.signinApproveCodeLabel),
              WebTextField(
                fieldKey: const Key('signin.code'),
                controller: _code,
                focusNode: _focus,
                label: l10n.signinApproveCodeLabel,
                placeholder: l10n.vaultApprovePlaceholder,
                invalid: enter.badCode,
                readOnly: busy,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.go,
                inputFormatters: [UpperCaseFormatter()],
                onChanged: (_) {
                  if (enter.badCode) setState(() => _view = const _Enter());
                },
                onSubmitted: (_) => _submit(busy),
              ),
              if (enter.badCode) FieldError(l10n.signinApproveBadCode),
              PressButton.text(
                busy ? l10n.vaultApproveFinding : l10n.vaultApproveSubmit,
                key: const Key('signin.submit'),
                onPressed: busy ? null : () => _submit(busy),
              ),
            ],
          ),
        ),
        _full(
          PressButton.text(
            l10n.vaultApproveCancel,
            key: const Key('signin.cancel'),
            tone: PressTone.ghost,
            onPressed: busy ? null : _close,
          ),
        ),
      ],
    );
  }

  void _submit(bool busy) {
    if (busy || _code.text.trim().isEmpty) return;
    unawaited(_find(code: _code.text));
  }
}
