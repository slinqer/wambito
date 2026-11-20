// The web's PasskeyOffer (apps/web/app/features/sign-in/PasskeyOffer.tsx): "¿Entrar con tu huella la
// próxima vez?", a passkey in plain words, and two ways out.
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import 'sign_in_frame.dart';

/// What making the passkey came to; `cancelled` is the person closing the phone's prompt.
/// `addedWithoutPrf`: an encrypted account's passkey was made, but it gave no PRF (its password
/// manager does not allow one): it signs in and does not open the data.
enum PasskeyOfferOutcome { added, addedWithoutPrf, cancelled, failed }

/// The passkey offer: what a passkey is, then "Crear mi huella" (the phone asks for the fingerprint
/// or face) or "Ahora no". Either answer ends the offer ([onAnswered], with whether a passkey was
/// made). Closing the phone's prompt is silent and the offer stays; a passkey that could not be
/// saved says so, and "Ahora no" is still there. While the prompt is open both buttons wait. A
/// passkey made without a PRF is kept, and the screen says so at once in text that stays
/// (`settingsPasskeysAddNoPrf`), with "Seguir" to go on (the web's PasskeyOffer).
class PasskeyOfferScreen extends StatefulWidget {
  const PasskeyOfferScreen({super.key, required this.add, required this.onAnswered});

  /// Makes the passkey for the signed-in person (the phone's prompt).
  final Future<PasskeyOfferOutcome> Function() add;

  /// The person answered; `true` when a passkey was made.
  final ValueChanged<bool> onAnswered;

  @override
  State<PasskeyOfferScreen> createState() => _PasskeyOfferScreenState();
}

class _PasskeyOfferScreenState extends State<PasskeyOfferScreen> {
  var _busy = false;
  var _failed = false;

  /// The passkey was made but opens nothing: the notice and "Seguir" replace the offer.
  var _withoutPrf = false;

  Future<void> _create() async {
    // Two quick taps must not open two prompts.
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    var outcome = PasskeyOfferOutcome.failed;
    try {
      outcome = await widget.add();
    } catch (_) {
      // Whatever went wrong, the offer says so and stays.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = outcome == PasskeyOfferOutcome.failed;
      _withoutPrf = outcome == PasskeyOfferOutcome.addedWithoutPrf;
    });
    if (outcome == PasskeyOfferOutcome.added) widget.onAnswered(true);
  }

  void _notNow() {
    if (!_busy) widget.onAnswered(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final points = [
      l10n.passkeyOfferKey,
      l10n.passkeyOfferUnlock,
      l10n.passkeyOfferSync,
      l10n.passkeyOfferBackup,
    ];
    if (_withoutPrf) {
      final colors = context.lkColors;
      return SignInFrame(
        children: [
          EntryTitle(l10n.passkeyOfferTitle),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              liveRegion: true,
              container: true,
              child: DecoratedBox(
                decoration: LkSurface.rowCard(context.lk),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    l10n.settingsPasskeysAddNoPrf,
                    key: const Key('offer.addNoPrf'),
                    style: LkText.note.copyWith(color: colors.ink),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: PressButton.text(
              l10n.passkeyOfferContinue,
              key: const Key('offer.continue'),
              onPressed: () => widget.onAnswered(true),
            ),
          ),
        ],
      );
    }
    return SignInFrame(
      children: [
        EntryTitle(l10n.passkeyOfferTitle),
        EntryLead(l10n.passkeyOfferLead),
        _Points(points),
        if (_failed) FieldError(l10n.passkeyOfferFailed),
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space2,
            children: [
              PressButton(
                key: const Key('offer.add'),
                onPressed: _busy ? null : _create,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: WambitoTokens.space2,
                  children: [
                    const FingerprintIcon(),
                    Flexible(
                      child: Text(
                        (_busy ? l10n.passkeyOfferAdding : l10n.passkeyOfferAdd).toUpperCase(),
                      ),
                    ),
                  ],
                ),
              ),
              PressButton.text(
                l10n.passkeyOfferNotNow,
                key: const Key('offer.notNow'),
                tone: PressTone.ghost,
                onPressed: _busy ? null : _notNow,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `<ul className="flex w-full list-disc flex-col gap-(--space-2) pl-(--space-5) text-ink
/// marker:text-ink-muted">`: the points, 24px in from the edge, each with a muted disc.
class _Points extends StatelessWidget {
  const _Points(this.points);

  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final style = LkText.copy.copyWith(color: colors.ink);
    return SizedBox(
      width: double.infinity,
      child: Semantics(
        container: true,
        child: Padding(
          padding: const EdgeInsets.only(left: WambitoTokens.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space2,
            children: [
              for (final point in points)
                CustomPaint(
                  painter: _DiscPainter(colors.inkMuted),
                  child: Text(point, style: style),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list item's `disc` marker, outside the text and before its first line.
class _DiscPainter extends CustomPainter {
  const _DiscPainter(this.color);

  final Color color;

  /// Where Blink draws it for a 16px font: a disc 5.6px across, its centre 14.4px before the text,
  /// at the middle of the first line.
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawCircle(const Offset(-14.4, 12), 2.8, Paint()..color = color);

  @override
  bool shouldRepaint(_DiscPainter old) => old.color != color;
}
