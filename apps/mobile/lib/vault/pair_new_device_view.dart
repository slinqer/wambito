// The web's PairNewDevice (apps/web/app/features/vault/PairNewDevice.tsx): a new phone opens its data
// from a device that has it. Shows a QR and the 8-character code (two groups of four), how long
// they work, then the number to compare once the other device answered. The other device approves;
// this one only waits. Nothing secret is logged: the QR holds the request's id and this phone's
// public key, the code and the number are shown and nothing else.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../entry/sign_in_frame.dart';
import '../home/wambi_face.dart';
import '../l10n/app_localizations.dart';
import '../local/keys_error.dart';
import '../local/pairing.dart' show PairingError;
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import 'vault_gate.dart';

/// What a pairing can end in, as shown; `cancelled` shows nothing.
enum PairingProblem { expired, tampered, offline, server }

/// A thrown error's code as a problem to show; null for a cancel (nothing to say). `bad_code` is
/// the approver's and never shows here.
PairingProblem? pairingProblem(Object error) {
  final code = switch (error) {
    PairingError(:final code) => code,
    KeysError(:final code) => code,
    GateError(:final code) => code,
    _ => null,
  };
  return switch (code) {
    'cancelled' || 'bad_code' => null,
    'expired' => PairingProblem.expired,
    'tampered' => PairingProblem.tampered,
    'offline' => PairingProblem.offline,
    _ => PairingProblem.server,
  };
}

var _zonesReady = false;

/// A time as `14:05` (es, it, pt) or `02:05 PM` (en), in the person's time zone (the phone's own
/// when the zone is unknown).
String formatPairingTime(String iso, String locale, String timeZone) {
  final at = DateTime.tryParse(iso);
  if (at == null) return iso;
  DateTime local;
  try {
    if (!_zonesReady) {
      tzdata.initializeTimeZones();
      _zonesReady = true;
    }
    local = tz.TZDateTime.from(at.toUtc(), tz.getLocation(timeZone));
  } on Object {
    local = at.toLocal();
  }
  String two(int n) => n.toString().padLeft(2, '0');
  if (locale != 'en') return '${two(local.hour)}:${two(local.minute)}';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '${two(hour)}:${two(local.minute)} ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// The code in two groups of four.
String _groups(String code) => '${code.substring(0, 4)} ${code.substring(4)}';

const _mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Roboto Mono', 'Courier'],
  fontWeight: FontWeight.w700,
);

/// The pairing link as a QR code, dark on white. [data] is `wambito://pair?id=...&key=...`; [label]
/// is what a screen reader says (never the link).
class PairingQr extends StatelessWidget {
  const PairingQr({super.key, required this.data, required this.label});

  final String data;
  final String label;

  @override
  Widget build(BuildContext context) =>
      QrImageView(data: data, size: 192, backgroundColor: Colors.white, semanticsLabel: label);
}

sealed class _View {
  const _View();
}

class _Starting extends _View {
  const _Starting();
}

class _Waiting extends _View {
  const _Waiting(this.request, this.number);

  final GatePairing<Object?> request;
  final String? number;
}

class _Done extends _View {
  const _Done();
}

class _Failed extends _View {
  const _Failed(this.problem);

  final PairingProblem problem;
}

class PairNewDeviceView extends StatefulWidget {
  const PairNewDeviceView({
    super.key,
    required this.start,
    required this.onBack,
    required this.timeZone,
  });

  /// Asks for a request (again on "Start again"; the gate cancels the previous one).
  final Future<GatePairing<Object?>> Function() start;

  /// Back to where the person came from (Unlock, or a guest's Locked); the gate cancels the request.
  final VoidCallback onBack;

  /// The account's time zone (`VaultProfile.timezone`), for the expiry.
  final String timeZone;

  @override
  State<PairNewDeviceView> createState() => _PairNewDeviceViewState();
}

class _PairNewDeviceViewState extends State<PairNewDeviceView> {
  _View _view = const _Starting();
  GatePairing<Object?>? _request;
  var _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  /// One request; a later "Start again" supersedes it (`_attempt`), and each is cancelled when it
  /// is left.
  Future<void> _begin() async {
    final attempt = ++_attempt;
    bool alive() => mounted && attempt == _attempt;
    void fail(Object error) {
      if (!alive()) return;
      final problem = pairingProblem(error);
      if (problem != null) setState(() => _view = _Failed(problem));
    }

    setState(() => _view = const _Starting());
    final GatePairing<Object?> started;
    try {
      started = await widget.start();
    } on Object catch (error) {
      fail(error);
      return;
    }
    if (!alive()) {
      started.cancel();
      return;
    }
    _request = started;
    setState(() => _view = _Waiting(started, null));
    unawaited(
      started.number().then((number) {
        if (alive()) setState(() => _view = _Waiting(started, number));
      }, onError: fail),
    );
    unawaited(
      started.finish().then((_) {
        if (alive()) setState(() => _view = const _Done());
      }, onError: fail),
    );
  }

  @override
  void dispose() {
    _attempt++;
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final back = SizedBox(
      width: double.infinity,
      child: PressButton.text(
        l10n.vaultPairBack,
        key: const Key('vault.pairBack'),
        tone: PressTone.ghost,
        onPressed: widget.onBack,
      ),
    );
    final view = _view;
    if (view is _Failed) {
      final problem = view.problem;
      final expired = problem == PairingProblem.expired;
      return SignInFrame(
        mood: WambiMood.worried,
        children: [
          EntryTitle(expired ? l10n.vaultPairExpiredTitle : l10n.vaultPairFailedTitle),
          if (expired)
            EntryLead(l10n.vaultPairExpiredLead)
          else
            FieldError(switch (problem) {
              PairingProblem.tampered => l10n.vaultPairTampered,
              PairingProblem.offline => l10n.vaultPairOffline,
              _ => l10n.vaultPairServer,
            }),
          if (problem != PairingProblem.tampered)
            SizedBox(
              width: double.infinity,
              child: PressButton.text(
                l10n.vaultPairRestart,
                key: const Key('vault.pairRestart'),
                onPressed: () => unawaited(_begin()),
              ),
            ),
          if (problem == PairingProblem.tampered)
            SizedBox(
              width: double.infinity,
              child: PressButton.text(
                l10n.vaultPairBack,
                key: const Key('vault.pairBack'),
                onPressed: widget.onBack,
              ),
            )
          else
            back,
        ],
      );
    }
    return SignInFrame(
      children: [
        EntryTitle(l10n.vaultPairTitle),
        if (view is _Starting)
          Semantics(liveRegion: true, container: true, child: EntryLead(l10n.vaultPairStarting)),
        if (view is _Done)
          Semantics(
            liveRegion: true,
            container: true,
            child: EntryLead(l10n.vaultPairDone, ink: true),
          ),
        if (view is _Waiting && view.number == null) ...[
          EntryLead(l10n.vaultPairLead),
          // The QR on white, whatever the theme: a scanner needs the contrast.
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(WambitoTokens.radiusMd),
            ),
            child: Padding(
              padding: const EdgeInsets.all(WambitoTokens.space2),
              // The code is on screen anyway; the link holds this phone's key.
              child: PairingQr(data: view.request.qr, label: view.request.code),
            ),
          ),
          Column(
            spacing: WambitoTokens.space1,
            children: [
              Text(l10n.vaultPairCodeLabel, style: LkText.note.copyWith(color: colors.inkMuted)),
              Text(
                _groups(view.request.code),
                key: const Key('vault.pairCode'),
                style: _mono.copyWith(fontSize: 28, letterSpacing: 3.4, color: colors.ink),
              ),
            ],
          ),
          Text(
            l10n.vaultPairExpires(
              formatPairingTime(view.request.expiresAt, l10n.localeName, widget.timeZone),
            ),
            textAlign: TextAlign.center,
            style: LkText.note.copyWith(color: colors.inkMuted),
          ),
          Semantics(liveRegion: true, container: true, child: EntryLead(l10n.vaultPairWaiting)),
        ],
        if (view is _Waiting && view.number != null) ...[
          Semantics(
            header: true,
            child: Text(
              l10n.vaultPairNumberTitle,
              textAlign: TextAlign.center,
              style: LkText.title.copyWith(color: colors.ink, fontSize: 18),
            ),
          ),
          Text(
            '${view.number!.substring(0, 3)} ${view.number!.substring(3)}',
            key: const Key('vault.pairNumber'),
            style: _mono.copyWith(fontSize: 40, height: 1, letterSpacing: 4.8, color: colors.ink),
          ),
          EntryLead(l10n.vaultPairNumberLead),
        ],
        if (view is! _Done) back,
      ],
    );
  }
}
