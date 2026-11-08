// The web's HomeHeader (apps/web/app/features/home/HomeHeader.tsx) and the CSS it uses: app.css
// `.lk-logo`, `.lk-avatar`, `.lk-menu`.
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/month_picker.dart';
import '../ui/pressable.dart';

/// Home's header: the wordmark, the month (earlier ones browsable, never past [max]) and the face
/// button, which opens the account menu ([menu]: the entries under it, as [HomeMenuLink]s). The
/// wordmark, the month and the two buttons need about 470px on one row, so under 480px (every
/// phone) the month gets its own centred row under the wordmark and the buttons, as on the web
/// (`min-[480px]`). Large text needs more room: the width is compared with 480px scaled like text,
/// so the buttons never wrap to a row of their own.
///
/// The menu is a disclosure: its button says whether it is open, a tap outside (or Back) closes it.
class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    required this.month,
    required this.onMonth,
    required this.max,
    required this.onSearch,
    this.menu,
  });

  /// The month shown, `YYYY-MM`.
  final String month;
  final ValueChanged<String> onMonth;

  /// The latest month to show: the current one in the person's time zone.
  final String max;

  /// The magnifier beside the face button: opens the search.
  final VoidCallback onSearch;

  /// What the menu holds, called with a function that closes it. Null: no menu.
  final Widget Function(BuildContext context, VoidCallback close)? menu;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _avatarKey = GlobalKey();
  var _open = false;

  /// The web's `min-[480px]`, a width of the viewport (scaled with the text here).
  static const _wide = 480.0;

  /// A finger came down at [position] with the menu open: anywhere but on the face button closes
  /// it (the button toggles it itself, as the web's `pointerdown` listener leaves it to).
  void _pressedOutside(Offset position) {
    final box = _avatarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      final local = box.globalToLocal(position);
      if (box.size.contains(local)) return;
    }
    _setOpen(false);
  }

  void _setOpen(bool open) {
    if (open == _open) return;
    setState(() => _open = open);
    if (open) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= MediaQuery.textScalerOf(context).scale(_wide);
    final picker = MonthPicker(month: widget.month, onChange: widget.onMonth, max: widget.max);
    // `<div className="flex items-center gap-(--space-2)">` with the search link and the face button.
    final avatar = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: WambitoTokens.space2,
      children: [
        _Avatar(
          buttonKey: const Key('home.search'),
          glyph: '🔍',
          label: l10n.searchTitle,
          onPressed: widget.onSearch,
        ),
        _Avatar(
          key: _avatarKey,
          buttonKey: const Key('home.account'),
          glyph: '🙂',
          label: l10n.homeAccount,
          open: _open,
          onPressed: widget.menu == null ? null : () => _setOpen(!_open),
        ),
      ],
    );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => _MenuLayer(
        link: _link,
        onClose: () => _setOpen(false),
        onPressedOutside: _pressedOutside,
        child: widget.menu!(context, () => _setOpen(false)),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            // `gap-x-(--space-2)`; the rows have no gap of their own.
            spacing: WambitoTokens.space2,
            children: [
              const LkWordmark(),
              if (wide) picker,
              avatar,
              // Narrow: the month is last (`order-last`) and takes a row to itself.
              if (!wide)
                SizedBox(
                  width: double.infinity,
                  child: Center(child: picker),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wordmark (`.lk-logo`): "Wambito" in Fredoka, painted with a gold to candy gradient, in a
/// line at least 44px tall.
class LkWordmark extends StatelessWidget {
  const LkWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Center(
        widthFactor: 1,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) =>
              LinearGradient(colors: [colors.gold, colors.candy]).createShader(bounds),
          child: Text(
            AppLocalizations.of(context).appName,
            style: LkText.logo.copyWith(color: const Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
  }
}

/// A round button of the header (`.lk-avatar`): the face button and the magnifier. A 44px round button that sinks 3px into a 1px edge, like the
/// month picker's arrows.
class _Avatar extends StatelessWidget {
  const _Avatar({
    super.key,
    required this.buttonKey,
    required this.glyph,
    required this.label,
    this.open,
    required this.onPressed,
  });

  /// Finds the button (tests).
  final Key buttonKey;
  final String glyph;
  final String label;

  /// Whether the menu it opens is open; null for a button that opens none.
  final bool? open;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final radius = LkSurface.radius(LkRadius.pill);
    return Semantics(
      container: true,
      expanded: open,
      child: Pressable(
        key: buttonKey,
        onPressed: onPressed,
        label: label,
        builder: (context, state) {
          final pressed = state.pressed;
          return PressSurface(
            pressDy: pressed ? 3 : 0,
            decoration: BoxDecoration(
              color: colors.surfaceRow,
              borderRadius: radius,
              border: LkSurface.border(colors),
              boxShadow: pressed ? LkSurface.pressedEdge(lk) : LkSurface.edgeShadow(lk, LkEdge.sm),
            ),
            ringRadius: state.focusVisible ? radius : null,
            ringColor: colors.focus,
            child: ExcludeSemantics(child: Text(glyph, style: LkText.avatarGlyph)),
          );
        },
      ),
    );
  }
}

/// The open menu (`.lk-menu absolute top-full right-0 z-20 mt-2 w-60`): 240px wide, under the
/// header at its right edge, 8px down. A press anywhere else closes it (and goes on to what is
/// there, as the web's `pointerdown` listener does); Back closes it too.
class _MenuLayer extends StatelessWidget {
  const _MenuLayer({
    required this.link,
    required this.onClose,
    required this.onPressedOutside,
    required this.child,
  });

  final LayerLink link;
  final VoidCallback onClose;
  final ValueChanged<Offset> onPressedOutside;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final layer = Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => onPressedOutside(event.position),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, WambitoTokens.space2),
          child: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 240,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: LkSurface.radius(LkRadius.lg),
                  border: LkSurface.border(colors),
                  boxShadow: LkSurface.edgeShadow(lk, LkEdge.md),
                ),
                child: Padding(
                  // `padding: var(--space-3)` inside the 2px border.
                  padding: const EdgeInsets.all(WambitoTokens.space3 + 2),
                  child: Material(
                    type: MaterialType.transparency,
                    child: DefaultTextStyle.merge(
                      style: LkText.bodySm.copyWith(color: colors.ink),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    // Back closes it (an app with a router; a bare test has none).
    if (Router.maybeOf(context) == null) return layer;
    return BackButtonListener(
      onBackButtonPressed: () async {
        onClose();
        return true;
      },
      child: layer,
    );
  }
}

/// One entry of the menu (the web's `min-h-11 flex items-center justify-between rounded-sm
/// text-[14px] font-bold` link): its name and a ›.
class HomeMenuLink extends StatelessWidget {
  const HomeMenuLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final radius = LkSurface.radius(LkRadius.sm);
    return Pressable(
      onPressed: onPressed,
      link: true,
      label: label,
      builder: (context, state) => RingBox(
        radius: state.focusVisible ? radius : null,
        color: colors.focus,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: LkText.bodySm.copyWith(
                    color: colors.ink,
                    decoration: state.pressed ? TextDecoration.underline : null,
                    decorationColor: colors.ink,
                  ),
                ),
              ),
              Text('›', style: LkText.bodySm.copyWith(color: colors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
