// The web's SegmentedControl (apps/web/app/ui/SegmentedControl.tsx) and the CSS it uses: app.css
// `.lk-seg`, `.lk-seg button`, `.lk-seg.has-thumb` and `.lk-seg-thumb`.
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';

import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import 'lk_theme.dart';
import 'pressable.dart';
import '../feedback/feedback.dart';

/// One option of a [SegmentedControl].
class SegmentOption<T> {
  const SegmentOption(this.value, this.label, {this.key});

  final T value;
  final String label;

  /// Finds this option's tab (tests).
  final Key? key;
}

/// Switches between views, as tabs: the selected option sits raised on its edge, only it is in
/// the tab order, and the arrow keys (wrapping), Home and End move the selection.
///
/// With [position] (where a pager is, in options: 0 is the first, 0.5 halfway to the second) the
/// raised thumb slides with it, following the finger; without it the selected option is raised in
/// place.
class SegmentedControl<T> extends StatefulWidget {
  const SegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.label,
    this.position,
  });

  final T value;
  final List<SegmentOption<T>> options;
  final ValueChanged<T> onChanged;

  /// Names the tab list for assistive technology.
  final String label;

  final ValueListenable<double>? position;

  @override
  State<SegmentedControl<T>> createState() => _SegmentedControlState<T>();
}

class _SegmentedControlState<T> extends State<SegmentedControl<T>> {
  final _nodes = <T, FocusNode>{};

  FocusNode _node(T value) => _nodes.putIfAbsent(value, () => FocusNode(debugLabel: 'tab $value'));

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _selectAt(int index) {
    final options = widget.options;
    final option = options[(index + options.length) % options.length];
    if (option.value != widget.value) context.feedback(FeedbackEvent.segmentChanged);
    widget.onChanged(option.value);
    _node(option.value).requestFocus();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final options = widget.options;
    final current = options.indexWhere((o) => o.value == widget.value);
    final next = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => current - 1,
      LogicalKeyboardKey.arrowRight => current + 1,
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => options.length - 1,
      _ => null,
    };
    if (next == null) return KeyEventResult.ignored;
    _selectAt(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final options = widget.options;
    final position = widget.position;
    final row = Row(
      spacing: 3,
      children: [
        for (final option in options)
          Expanded(
            child: _Tab(
              key: option.key,
              label: option.label,
              selected: option.value == widget.value,
              hasThumb: position != null,
              focusNode: _node(option.value)..skipTraversal = option.value != widget.value,
              onPressed: () {
                _node(option.value).requestFocus();
                if (option.value != widget.value) context.feedback(FeedbackEvent.segmentChanged);
                widget.onChanged(option.value);
              },
            ),
          ),
      ],
    );
    // The tab bar's semantics sit inside the 3 px padding, so the container is exactly its tabs:
    // a scroll that cuts through the padding never leaves it standing with no tab in it.
    final tabs = Semantics(
      container: true,
      role: SemanticsRole.tabBar,
      label: widget.label,
      child: position == null
          ? row
          : Stack(
              children: [
                Positioned.fill(
                  child: _Thumb(position: position, count: options.length),
                ),
                row,
              ],
            ),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: LkSurface.radius(LkRadius.md),
        ),
        child: Padding(padding: const EdgeInsets.all(3), child: tabs),
      ),
    );
  }
}

/// The selected look, on its own layer, moved by the pager's position (options are 3px apart):
/// `.lk-seg-thumb`, `transform: translateX(calc(p * 100% + p * 3px))` and a width of
/// `(100% - 6px - (count - 1) * 3px) / count` of the control (here, of the padded area, which is
/// the control less its 3px padding either side).
class _Thumb extends StatelessWidget {
  const _Thumb({required this.position, required this.count});

  final ValueListenable<double> position;
  final int count;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - (count - 1) * 3) / count;
        return ValueListenableBuilder<double>(
          valueListenable: position,
          builder: (context, p, _) => Align(
            alignment: Alignment.topLeft,
            child: Transform.translate(
              offset: Offset(p * (width + 3), 0),
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: lk.colors.surfaceRow,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: LkSurface.edgeShadow(lk, LkEdge.sm),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.selected,
    required this.hasThumb,
    required this.focusNode,
    required this.onPressed,
  });

  final String label;
  final bool selected;

  /// A pager's thumb draws the raised look: the selected tab has none of its own.
  final bool hasThumb;

  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    const radius = BorderRadius.all(Radius.circular(11));
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : WambitoTokens.durationPress;

    return Pressable(
      onPressed: onPressed,
      selected: selected,
      role: SemanticsRole.tab,
      focusNode: focusNode,
      builder: (context, state) {
        final pressed = state.pressed;
        // The selected tab sinks 3px into a 1px edge, the others 2px.
        final raised = selected && !hasThumb;
        return PressSurface(
          pressDy: pressed ? (selected ? 3 : 2) : 0,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: raised ? colors.surfaceRow : const Color(0x00000000),
            borderRadius: radius,
            boxShadow: raised
                ? (pressed ? LkSurface.pressedEdge(lk) : LkSurface.edgeShadow(lk, LkEdge.sm))
                : const [],
          ),
          ringRadius: state.focusVisible ? radius : null,
          ringColor: colors.focus,
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: Curves.ease,
            style: LkText.segment.copyWith(color: selected ? colors.ink : colors.inkMuted),
            child: Text(label),
          ),
        );
      },
    );
  }
}
