// The web's ApproveDevice (apps/web/app/features/vault/ApproveDevice.tsx): a phone whose data is
// open approves a new device. Type the code the new device shows (or scan its QR, where the phone
// can), compare the number on both screens, then "They match" seals the data key to it. "They do
// not match" cancels: nothing was shared. "They match" exists only once the number is shown.
//
// The scan is the phone's own full-screen camera (`wambito/scanner`, lib/scanner): it answers a
// text, and the screen has no camera view of its own. The pairing holds an ephemeral private key
// until it ends, so whenever the screen goes away before the approval is done (back, Cancel,
// "They do not match", a failure) the pairing is cancelled.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../entry/sign_in_frame.dart';
import '../../home/wambi_face.dart';
import '../../l10n/app_localizations.dart';
import '../../local/keys.dart' show KeysOptions;
import '../../local/pairing.dart' as pairing;
import '../../local/pairing.dart' show ApproverPairing;
import '../../scanner/qr_scanner.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.g.dart';
import '../../ui/lk_theme.dart';
import '../../ui/press_button.dart';
import '../../ui/web_text_field.dart';
import '../../vault/pair_new_device_view.dart' show PairingProblem, pairingProblem;

/// `findPairing` of `local/pairing.dart`; tests pass a fake one.
typedef FindPairing = Future<ApproverPairing> Function(
  KeysOptions options, {
  String? code,
  String? qr,
});

sealed class _View {
  const _View();
}

class _Enter extends _View {
  const _Enter({this.badCode = false, this.cameraFailed = false, this.busy = false});

  final bool badCode;
  final bool cameraFailed;
  final bool busy;
}

class _Waiting extends _View {
  const _Waiting();
}

class _Number extends _View {
  const _Number(this.pairing, this.number, {this.approving = false});

  final ApproverPairing pairing;
  final String number;
  final bool approving;
}

class _Done extends _View {
  const _Done();
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

class ApproveDeviceScreen extends ConsumerStatefulWidget {
  const ApproveDeviceScreen({
    super.key,
    required this.options,
    required this.onDone,
    this.findPairing = pairing.findPairing,
  });

  /// This phone's vault (its user, the network client and the key storage): the data key comes from
  /// its device wrap.
  final KeysOptions options;

  /// Closes the screen: done, nothing shared, or given up.
  final VoidCallback onDone;

  final FindPairing findPairing;

  @override
  ConsumerState<ApproveDeviceScreen> createState() => _ApproveDeviceScreenState();
}

class _ApproveDeviceScreenState extends ConsumerState<ApproveDeviceScreen> {
  _View _view = const _Enter();
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _canScan = false;

  /// The pairing in progress, cancelled when the screen goes away before it is done.
  ApproverPairing? _current;

  @override
  void initState() {
    super.initState();
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
    _release();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Lets go of the pairing in progress (its ephemeral private key); safe to call twice.
  void _release() {
    final current = _current;
    _current = null;
    current?.cancel();
  }

  void _fail(ApproverPairing? from, Object error) {
    if (from != null && _current != from) return;
    final problem = pairingProblem(error);
    if (problem == null) {
      // A `bad_code` is no problem to show on its own: it is the typed field's.
      if (error is pairing.PairingError && error.code == 'bad_code') {
        setState(() => _view = const _Enter(badCode: true));
      }
      return;
    }
    _release();
    setState(() => _view = _Failed(problem));
  }

  Future<void> _find({String? code, String? qr}) async {
    setState(() => _view = const _Enter(busy: true));
    final ApproverPairing found;
    try {
      found = await widget.findPairing(widget.options, code: code, qr: qr);
    } on Object catch (error) {
      if (mounted) _fail(null, error);
      return;
    }
    if (!mounted) {
      found.cancel();
      return;
    }
    _current = found;
    setState(() => _view = const _Waiting());
    try {
      final number = await found.number();
      if (mounted && _current == found) setState(() => _view = _Number(found, number));
    } on Object catch (error) {
      if (mounted) _fail(found, error);
    }
  }

  Future<void> _scan() async {
    setState(() => _view = const _Enter(busy: true));
    final String? text;
    try {
      text = await ref.read(qrScannerProvider).scan();
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

  Future<void> _approve(_Number view) async {
    setState(() => _view = _Number(view.pairing, view.number, approving: true));
    try {
      await view.pairing.approve();
    } on Object catch (error) {
      if (mounted) _fail(view.pairing, error);
      return;
    }
    if (!mounted || _current != view.pairing) return;
    _current = null;
    setState(() => _view = const _Done());
  }

  void _giveUp() {
    _release();
    widget.onDone();
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

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final view = _view;

    if (view is _Done || view is _Mismatch) {
      final done = view is _Done;
      return SignInFrame(
        mood: done ? WambiMood.celebrating : WambiMood.worried,
        children: [
          EntryTitle(done ? l10n.vaultApproveDoneTitle : l10n.vaultApproveMismatchTitle),
          EntryLead(done ? l10n.vaultApproveDoneLead : l10n.vaultApproveMismatchLead),
          _full(
            PressButton.text(
              l10n.vaultApproveClose,
              key: const Key('approve.close'),
              onPressed: widget.onDone,
            ),
          ),
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
          EntryTitle(expired ? l10n.vaultApproveExpiredTitle : l10n.vaultApproveFailedTitle),
          if (expired)
            EntryLead(l10n.vaultApproveExpiredLead)
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
                key: const Key('approve.restart'),
                onPressed: _startAgain,
              ),
            ),
          _full(
            PressButton.text(
              l10n.vaultApproveClose,
              key: const Key('approve.close'),
              tone: tampered ? PressTone.primary : PressTone.ghost,
              onPressed: widget.onDone,
            ),
          ),
        ],
      );
    }

    if (view is _Waiting || view is _Number) {
      return SignInFrame(
        children: [
          EntryTitle(l10n.vaultApproveTitle),
          if (view is _Number) ...[
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
              key: const Key('approve.number'),
              style: _mono.copyWith(fontSize: 40, height: 1, letterSpacing: 4.8, color: colors.ink),
            ),
            EntryLead(l10n.vaultApproveNumberLead),
            _full(
              PressButton.text(
                view.approving ? l10n.vaultApproveApproving : l10n.vaultApproveMatch,
                key: const Key('approve.match'),
                onPressed: view.approving ? null : () => unawaited(_approve(view)),
              ),
            ),
            _full(
              PressButton.text(
                l10n.vaultApproveNoMatch,
                key: const Key('approve.noMatch'),
                tone: PressTone.secondary,
                onPressed: view.approving
                    ? null
                    : () {
                        _release();
                        setState(() => _view = const _Mismatch());
                      },
              ),
            ),
          ] else ...[
            Semantics(
              liveRegion: true,
              container: true,
              child: EntryLead(l10n.vaultApproveWaiting),
            ),
            _full(
              PressButton.text(
                l10n.vaultApproveCancel,
                key: const Key('approve.cancel'),
                tone: PressTone.ghost,
                onPressed: _giveUp,
              ),
            ),
          ],
        ],
      );
    }

    final enter = view as _Enter;
    final busy = enter.busy;
    return SignInFrame(
      children: [
        EntryTitle(l10n.vaultApproveTitle),
        EntryLead(l10n.vaultApproveLead),
        if (_canScan)
          Column(
            spacing: WambitoTokens.space2,
            children: [
              _full(
                PressButton.text(
                  l10n.vaultApproveScan,
                  key: const Key('approve.scan'),
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
              FieldCaption(l10n.vaultApproveCodeLabel),
              WebTextField(
                fieldKey: const Key('approve.code'),
                controller: _code,
                focusNode: _focus,
                label: l10n.vaultApproveCodeLabel,
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
              if (enter.badCode) FieldError(l10n.vaultApproveErrorBadCode),
              PressButton.text(
                busy ? l10n.vaultApproveFinding : l10n.vaultApproveSubmit,
                key: const Key('approve.submit'),
                onPressed: busy ? null : () => _submit(busy),
              ),
            ],
          ),
        ),
        _full(
          PressButton.text(
            l10n.vaultApproveCancel,
            key: const Key('approve.cancel'),
            tone: PressTone.ghost,
            onPressed: busy ? null : _giveUp,
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

/// Upper case as the person types (the web's `uppercase` and `autoCapitalize="characters"`); the
/// text sent is the field's, which `findPairing` reads whatever its case.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) =>
      value.copyWith(text: value.text.toUpperCase());
}
