// The parts of home (apps/web/app/features/home/Home.tsx), put together from the web's components in
// lib/ui and the CSS Home.tsx uses: app.css `.lk-hero`, `.lk-hero-label`, `.lk-hero-meta`,
// `.lk-overline`, `.lk-nudge`, `.lk-tabs-sticky`.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/gen/wambito_api.dart';
import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/budget_bar.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/money.dart';
import '../ui/pixel_snap.dart';
import '../ui/press_button.dart';

/// The whole month's state against its total budget, as each category's is computed (the web's
/// `overallState`): near from 80 % of it (core's `NEAR_LIMIT_RATIO`), over past it.
BudgetState overallState(int budgetTotal, int spent) {
  if (budgetTotal <= 0) return spent > 0 ? BudgetState.over : BudgetState.ok;
  final ratio = spent / budgetTotal;
  return ratio > 1
      ? BudgetState.over
      : ratio >= 0.8
      ? BudgetState.near
      : BudgetState.ok;
}

/// What is left of the month (or, without budgets, what was spent), in large type: the label, the
/// amount and a bar with what was spent against the budgets (the web's `Hero`, a `.lk-hero`).
class HomeHero extends StatelessWidget {
  const HomeHero({super.key, required this.summary, required this.currency, this.pastMonth});

  final Summary summary;
  final String currency;

  /// The month's name (mid-sentence) when the figures are of an earlier month, so the labels never
  /// say "este mes" about another one. Null: this month.
  final String? pastMonth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final locale = l10n.localeName;
    final past = pastMonth;
    String money(int cents) => formatMoney(cents, currency, locale);
    final hasBudget = summary.budgetTotal > 0;
    final over = hasBudget && summary.remaining < 0;
    final label = !hasBudget
        ? (past == null ? l10n.homeSpentLabel : l10n.homeSpentLabelPast(past))
        : over
        ? (past == null ? l10n.homeOverLabel : l10n.homeOverLabelPast(past))
        : (past == null ? l10n.homeRemainingLabel : l10n.homeRemainingLabelPast(past));
    // `.lk-hero-amount` is `good`; `text-over` when over, `text-ink` without budgets.
    final amountColor = over ? colors.over : (hasBudget ? colors.good : colors.ink);
    final meta = LkText.meta.copyWith(color: colors.inkMuted);

    return Semantics(
      container: true,
      label: label,
      child: HeroCard(
        padding: const EdgeInsets.fromLTRB(
          WambitoTokens.space4,
          WambitoTokens.space3,
          WambitoTokens.space4,
          WambitoTokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: CssLines(
                style: LkText.heroLabel,
                child: Text(label, style: LkText.heroLabel.copyWith(color: colors.inkMuted)),
              ),
            ),
            CssLines(
              style: LkText.amountXl,
              child: Money(
                cents: hasBudget ? summary.remaining.abs() : summary.spent,
                currency: currency,
                animate: true,
                style: LkText.amountXl.copyWith(color: amountColor),
              ),
            ),
            if (hasBudget) ...[
              Padding(
                padding: const EdgeInsets.only(top: WambitoTokens.space2),
                child: BudgetBar(
                  spent: summary.spent,
                  budget: summary.budgetTotal,
                  state: overallState(summary.budgetTotal, summary.spent),
                  label: l10n.homeSpentMeter(money(summary.spent), money(summary.budgetTotal)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: CssLines(
                        style: LkText.meta,
                        child: Text(l10n.homeSpent(money(summary.spent)), style: meta),
                      ),
                    ),
                    Flexible(
                      child: CssLines(
                        style: LkText.meta,
                        child: Text(
                          l10n.homeOfBudget(money(summary.budgetTotal)),
                          style: meta,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: CssLines(
                  style: LkText.meta,
                  child: Text(l10n.homeNoBudgetMeta, style: meta),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The hero's place while the month loads: `lk-hero min-h-[140px]`, busy.
class HomeHeroPlaceholder extends StatelessWidget {
  const HomeHeroPlaceholder({super.key, this.label});

  /// What a screen reader says while it is empty.
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: const HeroCard(
      padding: EdgeInsets.fromLTRB(
        WambitoTokens.space4,
        WambitoTokens.space3,
        WambitoTokens.space4,
        WambitoTokens.space4,
      ),
      child: SizedBox(width: double.infinity, height: 140 - 12 - 16),
    ),
  );
}

/// `.lk-hero`: the `surface` card, radius `xl`, on `edge-md`.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.padding, required this.child, this.borderColor});

  final EdgeInsets padding;
  final Widget child;

  /// A 2px border of this colour inside the card (`.lk-danger-zone`). The card keeps its size, as
  /// a `border-box` does: the padding stays, and the content is that much narrower.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    // Chrome paints the card's edges on whole device pixels, wherever the page's lines put it.
    return SnappedDecoratedBox(
      decoration: BoxDecoration(
        color: lk.colors.surface,
        borderRadius: LkSurface.radius(LkRadius.xl),
        boxShadow: LkSurface.edgeShadow(lk, LkEdge.md),
        border: borderColor == null ? null : Border.all(color: borderColor!, width: 2),
      ),
      child: Padding(
        padding: borderColor == null ? padding : padding + const EdgeInsets.all(2),
        child: child,
      ),
    );
  }
}

/// A day's heading above its rows (`.lk-overline`, with `mt-1`): "Hoy · mié 21" and the day's
/// total, in `ink-muted`, upper case.
class DayHeading extends StatelessWidget {
  const DayHeading({super.key, required this.label, required this.total});

  final String label;
  final String total;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final style = LkText.eyebrow.copyWith(color: colors.inkMuted);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: WambitoTokens.space1, bottom: WambitoTokens.space2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: CssLines(
                style: LkText.eyebrow,
                child: Text(LkText.upperCase(label), style: style),
              ),
            ),
            CssLines(
              style: LkText.eyebrow,
              child: Text(
                total,
                style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card for an account that skipped the setup (`.lk-nudge`): a dashed outline, the title, what it
/// is for, the button it leads to, and "Ahora no" to put it away.
class NudgeCard extends StatelessWidget {
  const NudgeCard({
    super.key,
    required this.title,
    required this.lead,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
  });

  final String title;
  final String lead;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: title,
      child: CustomPaint(
        foregroundPainter: DashedBorderPainter(
          color: colors.stroke,
          radius: WambitoTokens.radiusLg,
          width: 2,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRow,
            borderRadius: BorderRadius.circular(WambitoTokens.radiusLg),
          ),
          child: Padding(
            // `padding: var(--space-3)` inside the 2px border.
            padding: const EdgeInsets.all(WambitoTokens.space3 + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WambitoTokens.space1,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: LkText.cardTitle.copyWith(color: colors.ink)),
                ),
                Text(lead, style: LkText.cardLead.copyWith(color: colors.inkMuted)),
                const SizedBox(height: WambitoTokens.space1),
                // The words have the card's whole width; the two buttons sit under them, the way
                // to it first and "Ahora no" at the end.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  spacing: WambitoTokens.space2,
                  children: [
                    Flexible(
                      child: PressButton.text(
                        actionLabel,
                        tone: PressTone.secondary,
                        size: PressSize.sm,
                        link: true,
                        onPressed: onAction,
                      ),
                    ),
                    PressButton.text(
                      l10n.notNow,
                      tone: PressTone.ghost,
                      size: PressSize.sm,
                      semanticLabel: l10n.homeNudgeDismiss(title),
                      onPressed: onDismiss,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The home cards side by side, one in view: a swipe shows the next, and dots under them say how
/// many there are and which is showing. One card is just the card. As tall as the tallest card, so
/// the page under it does not jump while swiping; a card put away leaves the others in place.
class NudgeCarousel extends StatefulWidget {
  const NudgeCarousel({super.key, required this.cards});

  final List<Widget> cards;

  @override
  State<NudgeCarousel> createState() => _NudgeCarouselState();
}

class _NudgeCarouselState extends State<NudgeCarousel> {
  static const _gap = WambitoTokens.space2;
  final _controller = ScrollController();
  int _page = 0;
  double _pageWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_pageWidth == 0) return;
    final page = (_controller.offset / _pageWidth).round().clamp(0, widget.cards.length - 1);
    if (page != _page) setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.length == 1) return cards.single;
    final colors = context.lkColors;
    final page = _page.clamp(0, cards.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // A page is a card and the gap after it: a turn lands the next card where the first
            // one was. Not clipped, so the cards' edges show, and the next one peeks in at the
            // screen's edge.
            _pageWidth = width + _gap;
            return SingleChildScrollView(
              key: const Key('home.nudges'),
              controller: _controller,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: _CardSnap(_pageWidth),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: _gap,
                  children: [for (final card in cards) SizedBox(width: width, child: card)],
                ),
              ),
            );
          },
        ),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              for (var i = 0; i < cards.length; i++)
                AnimatedContainer(
                  key: Key('home.nudges.dot.$i'),
                  duration: const Duration(milliseconds: 200),
                  width: i == page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == page ? colors.ink : colors.stroke,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Snaps a horizontal scroll to whole cards of [pageWidth] (card plus gap), as [PageScrollPhysics]
/// does to whole viewports: a fling goes to the next card, a slow drag to the nearest.
class _CardSnap extends ScrollPhysics {
  const _CardSnap(this.pageWidth, {super.parent});

  final double pageWidth;

  @override
  _CardSnap applyTo(ScrollPhysics? ancestor) => _CardSnap(pageWidth, parent: buildParent(ancestor));

  double _target(ScrollMetrics position, double velocity) {
    final still = toleranceFor(position).velocity;
    var page = position.pixels / pageWidth;
    if (velocity < -still) {
      page -= 0.5;
    } else if (velocity > still) {
      page += 0.5;
    }
    return (page.roundToDouble() * pageWidth).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final target = _target(position, velocity);
    if ((target - position.pixels).abs() < toleranceFor(position).distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// A dashed border as Blink draws one: each straight side is its own dashed line, starting with a
/// dash near where the side starts, dashes three widths long and gaps two (for borders under
/// 3px); the corners are drawn unbroken.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.width,
    this.bottomPhase = 0,
  });

  final Color color;
  final double radius;
  final double width;

  /// How far the bottom side's dashes sit further along than the nudge card's. Blink's phase on that
  /// side is not the same for every card (it was measured on the home nudge, and a card with a
  /// different height, the detail's archived note, starts 4px later): the caller says which.
  final double bottomPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final half = width / 2;
    final left = half;
    final top = half;
    final right = size.width - half;
    final bottom = size.height - half;
    final r = radius - half;
    // The corners.
    final corners = Path()
      ..addArc(Rect.fromLTWH(left, top, 2 * r, 2 * r), math.pi, math.pi / 2)
      ..addArc(Rect.fromLTWH(right - 2 * r, top, 2 * r, 2 * r), -math.pi / 2, math.pi / 2)
      ..addArc(Rect.fromLTWH(right - 2 * r, bottom - 2 * r, 2 * r, 2 * r), 0, math.pi / 2)
      ..addArc(Rect.fromLTWH(left, bottom - 2 * r, 2 * r, 2 * r), math.pi / 2, math.pi / 2);
    canvas.drawPath(corners, paint);
    // The sides.
    void side(Offset from, Offset to) {
      final length = (to - from).distance;
      final direction = (to - from) / length;
      final dash = width * 3;
      final gap = width * 2;
      for (var at = 0.0; at < length - 0.01; at += dash + gap) {
        final end = math.min(at + dash, length);
        canvas.drawLine(from + direction * at, from + direction * end, paint);
      }
    }

    // Where Chrome starts each side (measured on its picture of a 18px radius): the top and the
    // right and bottom sides read left to right and top to bottom, the left side too.
    side(Offset(left + r, top), Offset(right - r, top));
    side(Offset(right, top + r + 1.5), Offset(right, bottom - r));
    side(Offset(left + r + 1.5 + bottomPhase, bottom), Offset(right - r, bottom));
    side(Offset(left, top + r - 2), Offset(left, bottom - r));
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.width != width ||
      old.bottomPhase != bottomPhase;
}

/// The Movimientos | Categorías tabs, stuck under the top of the screen once the summary scrolls
/// away (`.lk-tabs-sticky`: 8px above and 4px below the control). It paints no fill of its own
/// (founder decision 2026-10-24): the tabs and the list sit on the page's own gradient, with no
/// darker band around them. [bleed] is the side padding of the content, which the strip reaches
/// past.
class HomeTabsStrip extends StatelessWidget {
  const HomeTabsStrip({super.key, required this.child, this.bleed = WambitoTokens.space4});

  final Widget child;

  /// How far the strip reaches past the content on each side (`-mx-4`).
  final double bleed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(bleed, WambitoTokens.space2, bleed, WambitoTokens.space1),
      child: child,
    );
  }
}

/// A spinner that does not move under "remove animations".
class QuietSpinner extends StatelessWidget {
  const QuietSpinner({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        value: MediaQuery.disableAnimationsOf(context) ? 0.25 : null,
      ),
    );
  }
}
