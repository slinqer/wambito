import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../money/format.dart';
import 'hide_amounts.dart';

/// What an amount reads as while home's eye is closed: the same for any amount and sign, so it
/// never hints at the size (the widget draws the same word).
const hiddenAmount = '••••';

/// [formatMoney], or [hiddenAmount] when [hidden]. For every amount that reaches the screen inside
/// a sentence or a label; a bare figure uses `Money`, which does this itself.
String shownMoney(
  bool hidden,
  int cents,
  String currency,
  String locale, {
  MoneySign sign = MoneySign.auto,
}) => hidden ? hiddenAmount : formatMoney(cents, currency, locale, sign: sign);

/// Whether amounts are hidden where [context] is: home's eye, as [HiddenAmountsScope] publishes it.
/// False with no scope above (a component drawn on its own).
bool hiddenAmountsOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_HiddenAmounts>()?.hidden ?? false;

/// Publishes home's eye to everything under it, so any widget (a `Consumer` or not) masks its
/// amounts and redraws the moment the eye flips. The app puts it at its root.
class HiddenAmountsScope extends ConsumerWidget {
  const HiddenAmountsScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _HiddenAmounts(hidden: ref.watch(amountsHiddenProvider), child: child);
}

class _HiddenAmounts extends InheritedWidget {
  const _HiddenAmounts({required this.hidden, required super.child});

  final bool hidden;

  @override
  bool updateShouldNotify(_HiddenAmounts old) => old.hidden != hidden;
}
