// The web's MonthPicker (apps/web/app/ui/MonthPicker.tsx) and the CSS it uses: app.css `.lk-step`.
import 'package:flutter/material.dart';

import '../home/home_format.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import 'lk_icons.dart';
import 'lk_theme.dart';
import 'pressable.dart';

/// The month [months] away from [month] (`YYYY-MM`), as the web's `addMonths` of @wambito/core.
String addMonths(String month, int months) {
  final parts = month.split('-').map(int.parse).toList();
  final index = parts[0] * 12 + (parts[1] - 1) + months;
  final year = index ~/ 12;
  final number = index % 12 + 1;
  return '${year.toString().padLeft(4, '0')}-${number.toString().padLeft(2, '0')}';
}

/// The month shown on home: previous and next arrows around the month's name (`Octubre`, with the
/// year when it differs from [max]'s: `Diciembre 2025`). "Next" stops at [max]. The name is a
/// polite live region, so stepping announces the new month.
class MonthPicker extends StatelessWidget {
  const MonthPicker({super.key, required this.month, required this.onChange, required this.max});

  /// The month shown, `YYYY-MM`.
  final String month;

  final ValueChanged<String> onChange;

  /// The latest month that can be shown (the current month in the person's time zone).
  final String max;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final name = formatMonthName(month, locale);
    final year = month.substring(0, 4);
    final label = year == max.substring(0, 4) ? name : '$name $year';
    final atMax = month.compareTo(max) >= 0;
    // The web's `min-[400px]:`: on narrower screens the name gives way (cut with …) and the gaps
    // shrink, so home's header stays one row down to 320px.
    final roomy = MediaQuery.sizeOf(context).width >= 400;

    return Semantics(
      container: true,
      label: l10n.monthPickerLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: roomy ? 8 : 4,
        children: [
          StepButton(
            icon: LkIconName.chevronLeft,
            label: l10n.monthPickerPrevious,
            onPressed: () => onChange(addMonths(month, -1)),
          ),
          // `min-[400px]:min-w-[7.5em]` of the 18px name.
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: roomy ? 7.5 * 18 : 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LkText.monthName.copyWith(color: context.lkColors.ink),
                ),
              ),
            ),
          ),
          StepButton(
            icon: LkIconName.chevronRight,
            label: l10n.monthPickerNext,
            onPressed: atMax ? null : () => onChange(addMonths(month, 1)),
          ),
        ],
      ),
    );
  }
}

/// An arrow (`.lk-step`): a 44px round button that sinks 3px into a 1px edge; disabled it is half
/// as opaque and does not move. The month picker's ‹ and ›, and the trend's under its chart.
class StepButton extends StatelessWidget {
  const StepButton({super.key, required this.icon, required this.label, required this.onPressed});

  final LkIconName icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final radius = LkSurface.radius(LkRadius.pill);
    return Pressable(
      onPressed: onPressed,
      label: label,
      builder: (context, state) {
        final pressed = state.pressed;
        final surface = PressSurface(
          pressDy: pressed ? 3 : 0,
          decoration: BoxDecoration(
            color: colors.surfaceRow,
            borderRadius: radius,
            border: LkSurface.border(colors),
            boxShadow: pressed ? LkSurface.pressedEdge(lk) : LkSurface.edgeShadow(lk, LkEdge.sm),
          ),
          ringRadius: state.focusVisible ? radius : null,
          ringColor: colors.focus,
          child: LkIcon(icon, size: 16, color: colors.ink),
        );
        return state.enabled ? surface : Opacity(opacity: 0.5, child: surface);
      },
    );
  }
}
