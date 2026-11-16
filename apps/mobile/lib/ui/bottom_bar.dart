// The web's BottomBar (apps/web/app/ui/BottomBar.tsx) and the CSS it uses: app.css `.lk-tabbar`,
// `.lk-tab` (and its press and focus), `.lk-tab-ico`, `.lk-plus` (and its press). The 🎤 beside
// the ＋ is the app's one addition to the web's layout (spec decision 3).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../feedback/celebration.dart';
import '../feedback/feedback.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import 'lk_icons.dart';
import 'lk_theme.dart';
import 'pressable.dart';

/// Phone navigation: Inicio · ＋ · Análisis. The raised ＋ (the bar's only `brand` element) opens
/// the add sheet; the 🎤 next to it, a smaller sibling in the same style, opens quick capture.
/// Recurring, categories and settings live in the avatar menu.
///
/// [current] is the current section (`home` or `insights`); one the bar has no tab for marks none.
/// [onNavigate] is called with `home` or `insights`.
///
/// The ＋ rises 14px above the tabs and past the bar's top edge, so the bar is 4px taller than its
/// drawn box: that strip is empty but for the ＋, which takes touches there too.
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.current,
    required this.onAdd,
    required this.onMic,
    required this.onNavigate,
    this.showMic = true,
    this.addKey,
    this.micKey,
  });

  final String current;

  /// Opens the add sheet.
  final VoidCallback onAdd;

  /// Opens quick capture, listening.
  final VoidCallback onMic;

  final ValueChanged<String> onNavigate;

  /// Whether the 🎤 shows. The parity pair with the web hides it (the web has none; the 🎤 has a
  /// picture of its own to review).
  final bool showMic;

  /// Keys for the ＋ and the 🎤 (home's tests and the emulator tests find them by key).
  final Key? addKey;
  final Key? micKey;

  /// How far the ＋ rises above the bar's drawn box.
  static const _rise = 4.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    // The tabs are 44px tall, or as tall as their 24px icon and label are at the phone's font size.
    final scaler = MediaQuery.textScalerOf(context);
    final tabs = math.max(44.0, 24 + 2 + scaler.scale(10 * 1.5).ceilToDouble());
    // Where the tabs end (the ＋ and the 🎤 stand on that line).
    final floor = _rise + 2 + 8 + tabs;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.navLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The tabs are 76px wide as the web draws them, unless the 🎤 would then touch the Análisis
          // tab (a phone narrower than the web's 380px column): they give up room, to 56px, so the 🎤
          // keeps 44px with 4px to spare on each side.
          const mic = 44.0;
          final barWidth = constraints.maxWidth;
          final tabWidth = ((barWidth - 12 - 58 - 3 * (mic + 2 * 4)) / 2).clamp(56.0, 76.0);
          // What `space-around` leaves between the ＋ and a tab, and where the 🎤 goes in it: 8px from the
          // ＋ when there is room, centred when there is not.
          final gap = (barWidth - 12 - (2 * tabWidth + 58)) / 3;
          final micGap = gap - mic >= 8 ? 8.0 : math.max(0.0, (gap - mic) / 2);
          return SizedBox(
            width: double.infinity,
            height: floor + 12,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // `.lk-tabbar`: `padding: 8px 6px 12px` under a 2px `stroke` line, on the sunken surface.
                Positioned(
                  left: 0,
                  right: 0,
                  top: _rise,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      border: Border(top: BorderSide(color: colors.stroke, width: 2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2 + 8, 6, 12),
                      child: SizedBox(
                        height: tabs,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _Tab(
                              width: tabWidth,
                              icon: LkIconName.home,
                              label: l10n.navHome,
                              current: current == 'home',
                              onPressed: () => onNavigate('home'),
                            ),
                            // Where the ＋ stands.
                            const SizedBox(width: 58, height: 44),
                            _Tab(
                              width: tabWidth,
                              icon: LkIconName.chart,
                              label: l10n.navInsights,
                              current: current == 'insights',
                              onPressed: () => onNavigate('insights'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // The ＋ shares its bottom with the tabs: 14px above their top.
                Positioned(
                  left: 0,
                  right: 0,
                  top: floor - 58,
                  height: 58,
                  child: Center(
                    // Wambi lands just above it when something is celebrated (the web's
                    // `data-celebration-anchor="64"` on the ＋).
                    child: CelebrationAnchor(
                      size: 64,
                      child: _RaisedButton(
                        key: addKey,
                        size: 58,
                        icon: LkIconName.plus,
                        iconSize: 26,
                        label: l10n.navAdd,
                        onPressed: onAdd,
                        pressedFeel: FeedbackEvent.addPressed,
                        releasedFeel: FeedbackEvent.addReleased,
                      ),
                    ),
                  ),
                ),
                if (showMic)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: floor - 44,
                    height: 44,
                    child: Center(
                      // [micGap] from the ＋'s right edge.
                      child: Transform.translate(
                        offset: Offset(29 + micGap + mic / 2, 0),
                        child: _RaisedButton(
                          key: micKey,
                          size: 44,
                          icon: LkIconName.mic,
                          iconSize: 22,
                          label: l10n.captureFabLabel,
                          onPressed: onMic,
                          pressedFeel: FeedbackEvent.micPressed,
                          releasedFeel: FeedbackEvent.micReleased,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// `.lk-tab`: an icon over a label, [width] wide (76px) and at least 44px tall. It has no edge: it dips 2px
/// while pressed. The current one is in `ink` with its icon filled, the others `ink-muted` and
/// outlined.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.width,
    required this.icon,
    required this.label,
    required this.current,
    required this.onPressed,
  });

  final double width;
  final LkIconName icon;
  final String label;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final radius = LkSurface.radius(LkRadius.md);
    return Pressable(
      onPressed: onPressed,
      link: true,
      selected: current,
      label: label,
      builder: (context, state) => RingBox(
        radius: state.focusVisible ? radius : null,
        color: colors.focus,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 80),
          curve: Curves.ease,
          transform: Matrix4.translationValues(0, state.pressed ? 2 : 0, 0),
          width: width,
          constraints: const BoxConstraints(minHeight: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 2,
            children: [
              LkIcon(
                icon,
                size: 24,
                variant: current ? LkIconVariant.filled : LkIconVariant.outline,
                color: current ? colors.ink : colors.inkMuted,
              ),
              BlinkLine(
                style: LkText.tab,
                child: Text(
                  label,
                  style: LkText.tab.copyWith(color: current ? colors.ink : colors.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.lk-plus`: a square of `brand` on its solid edge and glow, the bar's one raised element; it
/// sinks 5px into its edge while pressed. The 🎤 is the same, smaller.
///
/// It feels like a physical button: [pressedFeel] clicks as the finger lands and [releasedFeel]
/// as it lets go (the ＋'s firmer than the 🎤's).
class _RaisedButton extends StatelessWidget {
  const _RaisedButton({
    super.key,
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.onPressed,
    required this.pressedFeel,
    required this.releasedFeel,
  });

  final double size;
  final LkIconName icon;
  final double iconSize;
  final String label;
  final VoidCallback onPressed;
  final FeedbackEvent pressedFeel;
  final FeedbackEvent releasedFeel;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final radius = LkSurface.radius(LkRadius.lg);
    return Pressable(
      onPressed: onPressed,
      label: label,
      onFingerDown: () => context.feedback(pressedFeel),
      onFingerUp: () => context.feedback(releasedFeel),
      builder: (context, state) {
        final pressed = state.pressed;
        return PressSurface(
          minSize: 0,
          pressDy: pressed ? 5 : 0,
          decoration: BoxDecoration(
            color: colors.brand,
            borderRadius: radius,
            boxShadow: LkSurface.brandEdge(lk, pressed: pressed),
          ),
          ringRadius: state.focusVisible ? radius : null,
          ringColor: colors.focus,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: LkIcon(icon, size: iconSize, color: colors.onBrand),
            ),
          ),
        );
      },
    );
  }
}
