// The web's ApproveDevice (apps/web/app/features/vault/ApproveDevice.tsx): a phone whose data is
// open approves a new device. "Connect another device" (connect_device_screen.dart) finds the
// pairing by its typed code or its scanned QR and hands it here; this screen compares the number on
// both screens, then "They match" seals the data key to it. "They do not match" cancels: nothing was
// shared. "They match" exists only once the number is shown.
//
// The pairing holds an ephemeral private key until it ends, so whenever the screen goes away before
// the approval is done (back, Cancel, "They do not match", a failure) the pairing is cancelled.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../entry/sign_in_frame.dart';
import '../../home/wambi_face.dart';
import '../../l10n/app_localizations.dart';
import '../../local/pairing.dart' as pairing show PairingError;
import '../../local/pairing.dart' show ApproverPairing;
import '../../theme/text_styles.dart';
import '../../ui/lk_theme.dart';
import '../../ui/press_button.dart';
import '../../vault/pair_new_device_view.dart' show PairingProblem, pairingProblem;

sealed class _View {
  const _View();
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

class ApproveDeviceScreen extends StatefulWidget {
  const ApproveDeviceScreen({
    super.key,
    required this.pairing,
    required this.onStartAgain,
    required this.onDone,
  });

  /// The pairing found (`findPairing` of `local/pairing.dart`): its approver key is posted, the
  /// number comes next. This screen owns it from now on.
  final ApproverPairing pairing;

  /// "Start again" after a failure: back to the code or the scan.
  final VoidCallback onStartAgain;

  /// Closes the screen: done, nothing shared, or given up.
  final VoidCallback onDone;

  @override
  State<ApproveDeviceScreen> createState() => _ApproveDeviceScreenState();
}

class _ApproveDeviceScreenState extends State<ApproveDeviceScreen> {
  _View _view = const _Waiting();

  /// The pairing in progress, cancelled when the screen goes away before it is done.
  ApproverPairing? _current;

  @override
  void initState() {
    super.initState();
    _current = widget.pairing;
    unawaited(_waitForNumber(widget.pairing));
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  /// Lets go of the pairing in progress (its ephemeral private key); safe to call twice.
  void _release() {
    final current = _current;
    _current = null;
    current?.cancel();
  }

  void _fail(ApproverPairing from, Object error) {
    if (_current != from) return;
    var problem = pairingProblem(error);
    if (problem == null) {
      // A cancel says nothing. A `bad_code` belongs to the find, before this screen: here it is ours.
      if (error is! pairing.PairingError || error.code != 'bad_code') return;
      problem = PairingProblem.server;
    }
    _release();
    setState(() => _view = _Failed(problem!));
  }

  Future<void> _waitForNumber(ApproverPairing found) async {
    try {
      final number = await found.number();
      if (mounted && _current == found) setState(() => _view = _Number(found, number));
    } on Object catch (error) {
      if (mounted) _fail(found, error);
    }
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
    _release();
    widget.onStartAgain();
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
          Semantics(liveRegion: true, container: true, child: EntryLead(l10n.vaultApproveWaiting)),
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
}

/// Upper case as the person types (the web's `uppercase` and `autoCapitalize="characters"`); the
/// text sent is the field's, which `findPairing` and `findSigninRequest` read whatever its case.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) =>
      value.copyWith(text: value.text.toUpperCase());
}
