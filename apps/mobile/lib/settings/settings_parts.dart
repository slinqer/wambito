// The parts of the web's Settings (apps/web/app/features/settings/parts.tsx) and the CSS they use:
// app.css `.lk-hero` (the card), `.lk-switch-row`, `.lk-switch` and `.lk-switch-thumb`.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';

import '../home/home_widgets.dart' show HeroCard;
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/offset_underline.dart';
import '../ui/pixel_snap.dart';
import '../ui/press_button.dart';
import '../ui/pressable.dart';

/// A card of settings named by its heading (`SettingsSection`): `lk-hero`, 16px between what is in
/// it, the title in Fredoka 20 and, under it, a muted line on what the card is for.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.lead,
    this.danger = false,
    required this.children,
  });

  final String title;
  final String? lead;

  /// `tone="danger"`: deleting the account. The title is in the danger colour and the card has
  /// `.lk-danger-zone`'s border, 2px of the danger colour over the stroke's (55%).
  final bool danger;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final titleStyle = LkText.sectionTitle.copyWith(color: danger ? colors.over : colors.ink);
    final leadStyle = LkText.bodySm.copyWith(color: colors.inkMuted);
    final lead = this.lead;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: title,
      child: HeroCard(
        borderColor: danger ? Color.lerp(colors.stroke, colors.over, 0.55) : null,
        padding: const EdgeInsets.fromLTRB(
          WambitoTokens.space4,
          WambitoTokens.space3,
          WambitoTokens.space4,
          WambitoTokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WambitoTokens.space1,
              children: [
                // Blink puts the baseline of a title in its line box a pixel higher than Flutter does.
                Semantics(
                  header: true,
                  child: BlinkLine(
                    style: titleStyle,
                    child: CssParagraph(title, style: titleStyle),
                  ),
                ),
                if (lead != null) CssParagraph(lead, style: leadStyle),
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// The name of one setting and, under it, a muted line on what it does (`SettingLabel`).
class SettingLabel extends StatelessWidget {
  const SettingLabel({super.key, required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final labelStyle = LkText.body.copyWith(color: colors.ink);
    final hintStyle = LkText.fieldLabel.copyWith(color: colors.inkMuted);
    final hint = this.hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WambitoTokens.space1,
      children: [
        CssParagraph(label, style: labelStyle),
        if (hint != null) CssParagraph(hint, style: hintStyle),
      ],
    );
  }
}

/// One choice of a [Choices].
class Choice<T> {
  const Choice(this.value, this.label, {this.key});

  final T value;
  final String label;

  /// Finds this choice's label (tests).
  final Key? key;
}

/// One choice among a few (language, theme), as the web's native radios in a fieldset named by its
/// legend: the arrow keys move between them, only the chosen one is in the tab order, and the
/// chosen one is outlined in gold (`Choices`).
class Choices<T> extends StatefulWidget {
  const Choices({
    super.key,
    required this.legend,
    this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String legend;
  final String? hint;
  final T value;
  final List<Choice<T>> options;
  final ValueChanged<T> onChanged;

  @override
  State<Choices<T>> createState() => _ChoicesState<T>();
}

class _ChoicesState<T> extends State<Choices<T>> {
  final _nodes = <T, FocusNode>{};

  FocusNode _node(T value) =>
      _nodes.putIfAbsent(value, () => FocusNode(debugLabel: 'choice $value'));

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _select(T value) {
    _node(value).requestFocus();
    widget.onChanged(value);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final options = widget.options;
    final current = options.indexWhere((o) => o.value == widget.value);
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowDown => 1,
      _ => null,
    };
    if (step == null) return KeyEventResult.ignored;
    _select(options[(current + step + options.length) % options.length].value);
    return KeyEventResult.handled;
  }

  /// How many choices go on a line: all of them, as on the web, unless a label's longest word would
  /// then spill past its box's border (the app's five languages on a 360 px phone with the font at 130%).
  /// Then as few lines as fit, evenly filled (five in two lines: three and two).
  int _perRow(BuildContext context, double width) {
    final options = widget.options;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final style = DefaultTextStyle.of(context).style.merge(LkText.bodySm);
    var longest = 0.0;
    for (final option in options) {
      for (final word in option.label.split(' ')) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: direction,
          textScaler: scaler,
        )..layout();
        if (painter.width > longest) longest = painter.width;
        painter.dispose();
      }
    }
    // A word may run into the option's padding, as on the web ([_WholeWords]); not past its border.
    final cell = longest + 4;
    const gap = WambitoTokens.space2;
    final fit = ((width + gap) / (cell + gap)).floor().clamp(1, options.length);
    if (fit >= options.length) return options.length;
    final lines = (options.length / fit).ceil();
    return (options.length / lines).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final hint = widget.hint;
    final hintStyle = LkText.fieldLabel.copyWith(color: colors.inkMuted);
    return Semantics(
      container: true,
      role: SemanticsRole.radioGroup,
      label: widget.legend,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space2,
          children: [
            ExcludeSemantics(child: SettingLabel(label: widget.legend)),
            LayoutBuilder(
              builder: (context, constraints) {
                final options = widget.options;
                final perRow = _perRow(context, constraints.maxWidth);
                Widget option(Choice<T> option) => _Option(
                  label: option.label,
                  labelKey: option.key,
                  selected: option.value == widget.value,
                  focusNode: _node(option.value)..skipTraversal = option.value != widget.value,
                  onPressed: () => _select(option.value),
                );
                return Column(
                  spacing: WambitoTokens.space2,
                  children: [
                    for (var start = 0; start < options.length; start += perRow)
                      Row(
                        spacing: WambitoTokens.space2,
                        children: [
                          for (var i = start; i < start + perRow; i++)
                            Expanded(
                              child: i < options.length
                                  ? option(options[i])
                                  : const SizedBox.shrink(),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
            if (hint != null) CssParagraph(hint, style: hintStyle),
          ],
        ),
      ),
    );
  }
}

/// One radio, drawn as its label (`OPTION` in parts.tsx): 44px at least, `surface-row` with a 2px
/// `stroke` border and `edge-sm`; chosen, the border is `brand-glow`, the text `ink` and a 3px
/// `gold` outline stands 1px off it; with the keyboard on it, a 3px `focus` outline 2px off.
class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.labelKey,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
  });

  final String label;
  final Key? labelKey;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final radius = LkSurface.radius(LkRadius.md);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onPressed: onPressed,
        selected: selected,
        checked: selected,
        focusNode: focusNode,
        builder: (context, state) {
          final ring = state.focusVisible
              ? (colors.focus, 2.0)
              : selected
              ? (colors.gold, 1.0)
              : null;
          return RingBox(
            radius: ring == null ? null : radius,
            color: ring?.$1 ?? const Color(0x00000000),
            offset: ring?.$2 ?? 2,
            child: SnappedDecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceRow,
                borderRadius: radius,
                border: Border.all(color: selected ? colors.brandGlow : colors.stroke, width: 2),
                boxShadow: LkSurface.edgeShadow(lk, LkEdge.sm),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WambitoTokens.space2),
                  child: Center(
                    child: _WholeWords(
                      label,
                      textKey: labelKey,
                      style: LkText.bodySm.copyWith(color: selected ? colors.ink : colors.inkMuted),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// An on/off setting: the whole row is one switch, named by its label (`SettingSwitch`).
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.label,
    this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final labelStyle = LkText.body.copyWith(color: colors.ink);
    // The hint says `font-normal` (400), but the web loads Nunito from 600 up (fonts.ts), so the
    // browser draws its nearest face, 600.
    final hintStyle = LkText.fieldLabel.copyWith(
      color: colors.inkMuted,
      fontWeight: FontWeight.w600,
    );
    final hint = this.hint;
    return Pressable(
      onPressed: () => onChanged(!value),
      toggled: value,
      label: label,
      hint: hint,
      builder: (context, state) => RingBox(
        // `.lk-switch-row:focus-visible { outline: 3px solid var(--focus); outline-offset: 4px }`
        radius: state.focusVisible ? LkSurface.radius(LkRadius.md) : null,
        color: colors.focus,
        offset: 4,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            spacing: WambitoTokens.space3,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: WambitoTokens.space1,
                  children: [
                    CssParagraph(label, style: labelStyle),
                    if (hint != null) CssParagraph(hint, style: hintStyle),
                  ],
                ),
              ),
              LkSwitch(value: value),
            ],
          ),
        ),
      ),
    );
  }
}

/// The switch itself (`.lk-switch`): a 52 × 30 pill with a 2px border and a 20px thumb that slides
/// 22px, `brand` and white when on, `ink-muted` on the sunken surface when off.
class LkSwitch extends StatelessWidget {
  const LkSwitch({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : WambitoTokens.durationPress;
    final border = value ? colors.brand : colors.inkMuted;
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.ease,
        width: 52,
        height: 30,
        decoration: BoxDecoration(
          color: value ? colors.brand : colors.surfaceSunken,
          borderRadius: BorderRadius.circular(WambitoTokens.radiusPill),
          border: Border.all(color: border, width: 2),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: duration,
              curve: Curves.ease,
              left: value ? 3 + 22 : 3,
              top: 3,
              width: 20,
              height: 20,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.ease,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? colors.onBrand : colors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label centred in its box the way the web's flex label is: it wraps between words, never inside
/// one. A word wider than the room (the phone's font at 130 % makes "Automático" so) is not broken
/// at a letter: like the web's, the column keeps its width and the word spills evenly into the
/// padding on both sides.
class _WholeWords extends StatelessWidget {
  const _WholeWords(this.label, {required this.textKey, required this.style});

  final String label;

  /// The label's own [Text] carries it (tests find the label by it).
  final Key? textKey;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final merged = DefaultTextStyle.of(context).style.merge(style);
    final text = Text(label, key: textKey, style: style, textAlign: TextAlign.center);
    return LayoutBuilder(
      builder: (context, constraints) {
        var longest = 0.0;
        for (final word in label.split(' ')) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: merged),
            textDirection: direction,
            textScaler: scaler,
          )..layout();
          if (painter.width > longest) longest = painter.width;
          painter.dispose();
        }
        if (longest <= constraints.maxWidth) return text;
        // As tall as the label is when it has the room of its longest word.
        final width = longest.ceilToDouble();
        final painter = TextPainter(
          text: TextSpan(text: label, style: merged),
          textAlign: TextAlign.center,
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: width);
        final height = painter.height;
        painter.dispose();
        return SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: OverflowBox(
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: text,
          ),
        );
      },
    );
  }
}

/// A line of text as tall as CSS makes it ([CssLines]) with its baseline where Blink puts it
/// ([BlinkLine]): for the lines of a row (a name, "Creada el…", a region) whose line box is taller
/// than the text.
class CssBlinkLines extends StatelessWidget {
  const CssBlinkLines({super.key, required this.style, required this.child});

  final TextStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) => CssLines(
    style: style,
    child: BlinkLine(style: style, child: child),
  );
}

/// What a [SettingsRow] shows at its end (the web's `Trailing`).
sealed class RowTrailing {
  const RowTrailing();
}

/// A chevron, with a muted value before it when there is one.
class RowChevron extends RowTrailing {
  const RowChevron({this.value});

  final String? value;
}

/// A switch: the whole row is the switch.
class RowSwitch extends RowTrailing {
  const RowSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;
}

/// A small pill of text ("este dispositivo").
class RowChip extends RowTrailing {
  const RowChip(this.text);

  final String text;
}

/// Its own button, named by [label], that removes what the row stands for.
class RowTrash extends RowTrailing {
  const RowTrash({required this.label, required this.onTap, this.buttonKey});

  final String label;
  final VoidCallback onTap;

  /// Finds the trash button (tests).
  final Key? buttonKey;
}

/// A small button at the end ("Conectar", "Revocar"), named for screen readers by [semanticLabel]:
/// `secondary` for an action, `ghost` (underlined) for a quiet one. The rest of the row is not a
/// button.
class RowButton extends RowTrailing {
  const RowButton({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.tone = PressTone.secondary,
    this.buttonKey,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;
  final PressTone tone;

  /// Finds the button (tests).
  final Key? buttonKey;
}

/// Nothing at the end.
class RowNone extends RowTrailing {
  const RowNone();
}

/// The head of a [SettingsGroup] (the web's `SettingsGroupHead`): a 40px `surface-sunken` tile with
/// the [icon] in `brand`, the group's [title] and one muted [line] under it.
class SettingsGroupHead extends StatelessWidget {
  const SettingsGroupHead({super.key, required this.icon, required this.title, this.line});

  final Widget icon;
  final String title;
  final String? line;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final line = this.line;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        spacing: 12,
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: LkSurface.radius(LkRadius.sm),
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: colors.brand),
                    child: icon,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: LkText.cardTitle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
                if (line != null)
                  Text(
                    line,
                    style: LkText.fieldLabel.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A light group of rows (the web's `SettingsGroup`, app.css `.lk-group`): `surface-row` with a 2px
/// `stroke`, `radius-lg` and `edge-sm`, padding 10/12, an optional small uppercase label or a
/// [SettingsGroupHead], and a 2px `stroke` line between rows (and under the head), none above the
/// first row of a group without a head. Named by its label or its head's title.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.label, this.head, required this.rows});

  final String? label;
  final SettingsGroupHead? head;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final label = this.label;
    final head = this.head;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label ?? head?.title,
      child: SnappedDecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRow,
          borderRadius: LkSurface.radius(LkRadius.lg),
          border: Border.all(color: colors.stroke, width: 2),
          boxShadow: LkSurface.edgeShadow(lk, LkEdge.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (label != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                  child: ExcludeSemantics(
                    child: Text(
                      label.toUpperCase(),
                      style: LkText.label.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 11.5 * 0.06,
                        color: colors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ?head,
              // Each row with its own divider in a column of its own: the dividers share one key
              // (tests find them), and siblings may not.
              for (var i = 0; i < rows.length; i++)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (i > 0 || head != null)
                      Container(
                        key: const ValueKey('settings-row-divider'),
                        height: 2,
                        color: colors.stroke,
                      ),
                    rows[i],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of a [SettingsGroup] (the web's `SettingsRow`): an icon in a 32px box, a title with an
/// optional muted line (one line each, ellipsis) and a [RowTrailing]. A [RowSwitch] row is one
/// switch named by its title; a [RowTrash] row has its own button, and the rest of the row is
/// pressable only with [onTap]; [danger] colours the title and icon with `over`.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.line,
    required this.trailing,
    this.onTap,
    this.danger = false,
    this.semanticsHint,
  });

  final Widget icon;
  final String title;
  final String? line;
  final RowTrailing trailing;
  final VoidCallback? onTap;
  final bool danger;

  /// What a screen reader hears under a switch row's name instead of [line] (the full wording of a
  /// short line).
  final String? semanticsHint;

  Widget _body(BuildContext context, {required Widget? end}) =>
      LayoutBuilder(builder: (context, constraints) => _bodyIn(context, constraints.maxWidth, end));

  Widget _bodyIn(BuildContext context, double width, Widget? end) {
    final colors = context.lkColors;
    final line = this.line;
    final tint = danger ? colors.over : colors.inkMuted;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 9, 0, 9),
        child: Row(
          spacing: 12,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: tint),
                  child: icon,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LkText.cardTitle.copyWith(color: danger ? colors.over : colors.ink),
                  ),
                  if (line != null)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LkText.fieldLabel.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.inkMuted,
                      ),
                    ),
                ],
              ),
            ),
            // The end never takes more than 45 % of the row, so the title keeps its room.
            if (end != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width * 0.45),
                child: end,
              ),
          ],
        ),
      ),
    );
  }

  Widget _pressable(BuildContext context, Widget child) {
    final colors = context.lkColors;
    return Pressable(
      onPressed: onTap,
      builder: (context, state) => RingBox(
        radius: state.focusVisible ? LkSurface.radius(LkRadius.md) : null,
        color: colors.focus,
        offset: 2,
        child: Opacity(opacity: state.pressed ? 0.7 : 1, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final t = trailing;
    switch (t) {
      case RowSwitch():
        return Pressable(
          onPressed: () => t.onChanged(!t.value),
          toggled: t.value,
          label: title,
          hint: semanticsHint ?? line,
          builder: (context, state) => RingBox(
            radius: state.focusVisible ? LkSurface.radius(LkRadius.md) : null,
            color: colors.focus,
            offset: 2,
            child: _body(
              context,
              end: Transform.scale(scale: 0.85, child: LkSwitch(value: t.value)),
            ),
          ),
        );
      case RowTrash():
        final main = _body(context, end: null);
        return Row(
          spacing: 4,
          children: [
            Expanded(child: onTap == null ? main : _pressable(context, main)),
            Pressable(
              key: t.buttonKey,
              onPressed: t.onTap,
              label: t.label,
              builder: (context, state) => RingBox(
                radius: state.focusVisible ? LkSurface.radius(LkRadius.md) : null,
                color: colors.focus,
                offset: 0,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Opacity(
                      opacity: state.pressed ? 0.7 : 1,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: LkIcon(LkIconName.trash, size: 18, color: colors.over),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case RowChevron():
        final value = t.value;
        final end = Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            if (value != null)
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LkText.label.copyWith(color: colors.inkMuted),
                ),
              ),
            LkIcon(LkIconName.chevronRight, size: 16, color: colors.inkMuted),
          ],
        );
        final body = _body(context, end: end);
        return onTap == null ? body : _pressable(context, body);
      case RowChip():
        final end = DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(WambitoTokens.radiusPill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(t.text, style: LkText.label.copyWith(fontSize: 11, color: colors.inkMuted)),
          ),
        );
        final body = _body(context, end: end);
        return onTap == null ? body : _pressable(context, body);
      case RowButton():
        final text = LkText.upperCase(t.label);
        final end = PressButton(
          key: t.buttonKey,
          tone: t.tone,
          size: PressSize.sm,
          semanticLabel: t.semanticLabel,
          onPressed: t.onPressed,
          child: t.tone == PressTone.ghost ? OffsetUnderline(text) : Text(text),
        );
        final body = _body(context, end: end);
        return onTap == null ? body : _pressable(context, body);
      case RowNone():
        final body = _body(context, end: null);
        return onTap == null ? body : _pressable(context, body);
    }
  }
}
