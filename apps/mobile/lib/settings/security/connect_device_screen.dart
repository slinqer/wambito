// "Connect another device" (Settings → Security): one entry for both ways another screen joins
// this account, which look alike to the person (a QR and an 8-character code): a web sign-in
// (`/v2/signin`, `wambito://signin?…`, phone-first spec 8.1) and a new device to approve
// (`/v2/pairing`, `wambito://pair?…`). One scan takes either QR and goes by its prefix; a typed code
// is looked up as a web sign-in first (a lookup posts nothing) and, when that finds nothing
// (`bad_code`), as a device to approve. Both codes are random, so they do not collide.
//
// What is found goes to its own confirmation, unchanged: `ApproveSigninScreen` (its warning, the
// 1 s wait before Approve, the number for a typed code) or `ApproveDeviceScreen` (the number
// compared). Their "Start again" comes back here. While this screen is open a `wambito://signin`
// link is dropped, as while the sign-in screen is (`openSigninApprovalsProvider`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../entry/sign_in_frame.dart';
import '../../home/wambi_face.dart';
import '../../l10n/app_localizations.dart';
import '../../local/pairing.dart' show ApproverPairing;
import '../../local/signin_approval.dart' show SigninApproval;
import '../../scanner/qr_scanner.dart';
import '../../theme/tokens.g.dart';
import '../../ui/press_button.dart';
import '../../ui/web_text_field.dart';
import '../../vault/pair_new_device_view.dart' show PairingProblem;
import 'approve_device_screen.dart';
import 'approve_signin_screen.dart';
import 'security_api.dart';

sealed class _View {
  const _View();
}

class _Enter extends _View {
  const _Enter({this.badCode = false, this.cameraFailed = false, this.busy = false, this.problem});

  final bool badCode;
  final bool cameraFailed;
  final bool busy;

  /// The lookup failed (offline, the server, …): said under the field, which stays.
  final PairingProblem? problem;
}

class _Signin extends _View {
  const _Signin(this.approval);

  final SigninApproval approval;
}

class _Pairing extends _View {
  const _Pairing(this.pairing);

  final ApproverPairing pairing;
}

/// A lookup's error as what to show; null for a cancel (nothing to say) and for `bad_code`.
PairingProblem? _problemOf(Object error) => switch (codeOf(error)) {
  'cancelled' || 'bad_code' => null,
  'expired' => PairingProblem.expired,
  'tampered' => PairingProblem.tampered,
  'offline' => PairingProblem.offline,
  _ => PairingProblem.server,
};

class ConnectDeviceScreen extends ConsumerStatefulWidget {
  const ConnectDeviceScreen({super.key, this.onDone});

  /// Closes the screen; by default it pops its route.
  final VoidCallback? onDone;

  @override
  ConsumerState<ConnectDeviceScreen> createState() => _ConnectDeviceScreenState();
}

class _ConnectDeviceScreenState extends ConsumerState<ConnectDeviceScreen> {
  _View _view = const _Enter();
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _canScan = false;
  late final OpenSigninApprovals _registry;

  @override
  void initState() {
    super.initState();
    _registry = ref.read(openSigninApprovalsProvider)..open(this);
    unawaited(_checkScanner());
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
    _registry.close(this);
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _startAgain() {
    _code.clear();
    setState(() => _view = const _Enter());
  }

  /// Finds what a [qr] (by its prefix) or a typed [code] (a web sign-in first) points at.
  Future<Object> _lookUp(SecurityApi security, {String? code, String? qr}) async {
    if (qr != null) {
      return qr.startsWith(signinQrPrefix)
          ? await security.findSigninRequest(qr: qr)
          : await security.findPairing(qr: qr);
    }
    try {
      return await security.findSigninRequest(code: code);
    } on Object catch (error) {
      if (codeOf(error) != 'bad_code') rethrow;
    }
    return security.findPairing(code: code);
  }

  Future<void> _find({String? code, String? qr}) async {
    final security = ref.read(securityApiProvider);
    if (security == null) return;
    setState(() => _view = const _Enter(busy: true));
    final Object found;
    try {
      found = await _lookUp(security, code: code, qr: qr);
    } on Object catch (error) {
      if (!mounted) return;
      final problem = _problemOf(error);
      setState(
        () => _view = problem != null
            ? _Enter(problem: problem)
            : _Enter(badCode: codeOf(error) == 'bad_code'),
      );
      return;
    }
    if (!mounted) {
      if (found is SigninApproval) found.cancel();
      if (found is ApproverPairing) found.cancel();
      return;
    }
    setState(
      () => _view = found is SigninApproval ? _Signin(found) : _Pairing(found as ApproverPairing),
    );
  }

  Future<void> _scan() async {
    setState(() => _view = const _Enter(busy: true));
    final String? text;
    try {
      text = await ref.read(qrScannerProvider).scan(prefixes: const [pairQrPrefix, signinQrPrefix]);
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

  void _submit(bool busy) {
    if (busy || _code.text.trim().isEmpty) return;
    unawaited(_find(code: _code.text));
  }

  Widget _full(Widget child) => SizedBox(width: double.infinity, child: child);

  @override
  Widget build(BuildContext context) {
    final view = _view;
    // The confirmations are their own screens (their own back, their own release of the key).
    if (view is _Signin) {
      return ApproveSigninScreen(
        key: ObjectKey(view.approval),
        found: view.approval,
        onStartAgain: _startAgain,
        onDone: _close,
      );
    }
    if (view is _Pairing) {
      return ApproveDeviceScreen(
        key: ObjectKey(view.pairing),
        pairing: view.pairing,
        onStartAgain: _startAgain,
        onDone: _close,
      );
    }
    return Scaffold(body: _enter(context, view as _Enter));
  }

  Widget _enter(BuildContext context, _Enter enter) {
    final l10n = AppLocalizations.of(context);
    final busy = enter.busy;
    final cancel = _full(
      PressButton.text(
        l10n.vaultApproveCancel,
        key: const Key('connect.cancel'),
        tone: PressTone.ghost,
        onPressed: busy ? null : _close,
      ),
    );

    if (ref.watch(securityApiProvider) == null) {
      return SignInFrame(
        mood: WambiMood.worried,
        children: [
          EntryTitle(l10n.settingsSecurityConnect),
          EntryLead(l10n.signinApproveLocked),
          cancel,
        ],
      );
    }

    final problem = enter.problem;
    return SignInFrame(
      children: [
        EntryTitle(l10n.settingsSecurityConnect),
        EntryLead(l10n.settingsSecurityConnectLead),
        if (_canScan)
          Column(
            spacing: WambitoTokens.space2,
            children: [
              _full(
                PressButton.text(
                  l10n.vaultApproveScan,
                  key: const Key('connect.scan'),
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
              FieldCaption(l10n.connectDeviceCodeLabel),
              WebTextField(
                fieldKey: const Key('connect.code'),
                controller: _code,
                focusNode: _focus,
                label: l10n.connectDeviceCodeLabel,
                placeholder: l10n.vaultApprovePlaceholder,
                invalid: enter.badCode,
                readOnly: busy,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.go,
                inputFormatters: [UpperCaseFormatter()],
                onChanged: (_) {
                  if (enter.badCode || problem != null) setState(() => _view = const _Enter());
                },
                onSubmitted: (_) => _submit(busy),
              ),
              if (enter.badCode) FieldError(l10n.connectDeviceBadCode),
              if (problem != null)
                FieldError(switch (problem) {
                  PairingProblem.expired => l10n.vaultApproveExpiredTitle,
                  PairingProblem.tampered => l10n.vaultApproveTampered,
                  PairingProblem.offline => l10n.vaultApproveOffline,
                  PairingProblem.server => l10n.vaultApproveServer,
                }),
              PressButton.text(
                busy ? l10n.vaultApproveFinding : l10n.vaultApproveSubmit,
                key: const Key('connect.submit'),
                onPressed: busy ? null : () => _submit(busy),
              ),
            ],
          ),
        ),
        cancel,
      ],
    );
  }
}
