import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../privacy/masked_money.dart';
import '../theme/tokens.g.dart';

/// An amount in the app's language (`562,92 €` / `€562.92`) with tabular figures: the web's
/// `Money` (apps/web/app/ui/Money.tsx). [style] is what the web's `className` gives it, e.g.
/// `LkText.amountXl` in the theme's `good` for the hero (`lk-hero-amount`), or `LkText.amount`
/// for a row (`lk-amount`).
///
/// With [animate], a change counts from the previous value to the new one over `--count-up`
/// (ease-out); the counting figure is hidden from assistive technology, which reads the final
/// amount right away. With [countFrom] it also counts up from that value when it first shows.
/// With "remove animations" (reduced motion) the value just changes.
class Money extends StatefulWidget {
  const Money({
    super.key,
    required this.cents,
    required this.currency,
    this.animate = false,
    this.countFrom,
    this.style,
  });

  /// Integer minor units; negatives show the real minus sign (U+2212).
  final int cents;

  /// ISO 4217 code, e.g. `EUR`.
  final String currency;

  /// Count from the previous value to the new one whenever [cents] changes.
  final bool animate;

  /// With [animate]: count up from this value when it first shows (0, say), not only on changes.
  final int? countFrom;

  /// The text style, on top of the surrounding one; the figures are always tabular (`lk-num`).
  final TextStyle? style;

  @override
  State<Money> createState() => _MoneyState();
}

class _MoneyState extends State<Money> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: WambitoTokens.durationCountUp,
  );

  /// motion's "easeOut", cubic-bezier(0, 0, 0.58, 1): Flutter's [Curves.easeOut].
  late final _eased = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  late int _from;
  late int _to;
  var _started = false;

  bool get _counting => widget.animate && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _to = widget.cents;
    _from = _counting ? (widget.countFrom ?? widget.cents) : widget.cents;
    if (_from != _to) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(Money old) {
    super.didUpdateWidget(old);
    if (old.cents == widget.cents) return;
    final shown = _shown;
    _to = widget.cents;
    if (!_counting || shown == _to) {
      _from = _to;
      _controller.value = 1;
      return;
    }
    _from = shown;
    _controller.forward(from: 0);
  }

  /// The figure on screen now.
  int get _shown => (_from + (_to - _from) * _eased.value).round();

  @override
  void dispose() {
    _eased.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'es';
    final style = (widget.style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Home's eye closed: one masked word, no count, read as "amount hidden".
    if (hiddenAmountsOf(context)) {
      return Semantics(
        label: AppLocalizations.of(context).amountHidden,
        child: ExcludeSemantics(child: Text(hiddenAmount, style: style)),
      );
    }
    final last = formatMoney(widget.cents, widget.currency, locale);
    if (!widget.animate) return Text(last, style: style);
    return Semantics(
      label: last,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _eased,
          builder: (context, _) => Text(
            formatMoney(_counting ? _shown : widget.cents, widget.currency, locale),
            style: style,
          ),
        ),
      ),
    );
  }
}
