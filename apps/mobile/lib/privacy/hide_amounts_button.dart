import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/feedback.dart';
import '../l10n/app_localizations.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import 'hide_amounts.dart';

/// Home's eye, right after the hero figure: hides every amount in the app (the blind comes down)
/// or shows them again (the blind goes up). An open eye while they show, a crossed one while hidden;
/// a 48 × 40 dp target, the figure's line.
class HideAmountsButton extends ConsumerWidget {
  const HideAmountsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(amountsHiddenProvider);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      label: hidden ? l10n.showAmounts : l10n.hideAmounts,
      excludeSemantics: true,
      child: InkResponse(
        radius: 24,
        onTap: () {
          ref.read(feedbackProvider)(
            hidden ? FeedbackEvent.amountsShown : FeedbackEvent.amountsHidden,
          );
          ref.read(amountsHiddenProvider.notifier).set(!hidden);
        },
        // 48 wide, but only as tall as the hero figure's line (38 px at 1.05): a taller button
        // would grow the hero and push the first rows down a short phone's screen.
        child: SizedBox(
          width: 48,
          height: 40,
          child: Center(
            child: LkIcon(
              hidden ? LkIconName.eyeOff : LkIconName.eye,
              size: 24,
              color: context.lk.colors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
