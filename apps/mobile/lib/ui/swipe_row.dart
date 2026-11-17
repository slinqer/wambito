// The web's SwipeRow (apps/web/app/ui/SwipeRow.tsx) and the CSS it uses: app.css `.lk-swipe`,
// `.lk-swipe-face`, `.lk-swipe-side`, `.lk-swipe-action`, `.lk-swipe-glyph`. How the gestures
// behave (the axis, the thresholds, the springs) is `swipe_rules.dart`'s, Stage 3's rules.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';

import '../feedback/feedback.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import 'lk_theme.dart';
import 'swipe_rules.dart';

/// What swiping a row to the right does: "Editar", or "Pagado" on a pending row.
enum SwipeRightKind { edit, paid }

/// The right-hand action of a [SwipeRow].
class SwipeRight {
  const SwipeRight(this.kind, this.run, this.label);

  final SwipeRightKind kind;

  /// Runs as the row springs back.
  final VoidCallback run;

  /// "Editar" or "Pagado".
  final String label;
}

/// What a [SwipeRow]'s swipes do, in words, for the row inside it to describe itself with (the web's
/// `useSwipeHint`): screen readers take over one-finger swipes, so the row's own button names what
/// it can do instead.
class SwipeHint extends InheritedWidget {
  const SwipeHint({super.key, required this.hint, required super.child});

  final String? hint;

  /// The hint of the [SwipeRow] above [context], if any.
  static String? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SwipeHint>()?.hint;

  @override
  bool updateShouldNotify(SwipeHint old) => old.hint != hint;
}

/// Shared by the rows of one list: only one row is open at a time, and a tap anywhere else, or a
/// scroll, closes it (the web's `closeOpenRow`).
class SwipeGroup {
  VoidCallback? _close;
  bool Function(Offset globalPosition)? _contains;

  /// A row opened: the one open before closes.
  void opened(VoidCallback close, bool Function(Offset) contains) {
    if (_close != null && _close != close) _close!();
    _close = close;
    _contains = contains;
  }

  void closed(VoidCallback close) {
    if (_close == close) {
      _close = null;
      _contains = null;
    }
  }

  /// Closes the open row, if any.
  void closeOpen() => _close?.call();

  /// A finger came down at [globalPosition]: anywhere but on the open row closes it.
  void pointerDown(Offset globalPosition) {
    final contains = _contains;
    if (contains != null && !contains(globalPosition)) closeOpen();
  }
}

/// Gives the rows below it their [SwipeGroup], and closes the open row on a tap elsewhere or a
/// scroll.
class SwipeScope extends StatefulWidget {
  const SwipeScope({super.key, required this.child});

  final Widget child;

  static SwipeGroup? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SwipeScope>()?.group;

  @override
  State<SwipeScope> createState() => _SwipeScopeState();
}

class _SwipeScopeState extends State<SwipeScope> {
  final _group = SwipeGroup();

  @override
  Widget build(BuildContext context) {
    return _SwipeScope(
      group: _group,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _group.pointerDown(event.position),
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (_) {
            _group.closeOpen();
            return false;
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _SwipeScope extends InheritedWidget {
  const _SwipeScope({required this.group, required super.child});

  final SwipeGroup group;

  @override
  bool updateShouldNotify(_SwipeScope old) => old.group != group;
}

/// One finger's drag along the row's axis. It decides the axis once the finger has moved past the
/// slop: sideways only when the move is more sideways than down (a perfect diagonal scrolls).
/// Sideways, it wins the gesture and the row follows the finger; otherwise it steps aside and the
/// list scrolls untouched. The web's `useAxisDrag` (apps/web/app/ui/use-axis-drag.ts).
class RowDragRecognizer extends OneSequenceGestureRecognizer {
  RowDragRecognizer({super.debugOwner, super.supportedDevices});

  /// A finger came down on the row. Stop any spring here (a touch catches the row where it is) and
  /// return false to ignore the touch altogether.
  bool Function()? onStart;

  /// The gesture just turned sideways: it is a drag from now on.
  VoidCallback? onLock;

  /// Every move: `dx` from where the finger came down.
  ValueChanged<double>? onMove;

  /// The drag ended: `vx` is the finger's speed in px/s (0 when it was cancelled).
  void Function(double dx, double vx)? onRelease;

  /// The touch ended without becoming a drag (a tap, a move the other way): whatever [onStart]
  /// stopped must go back to rest now.
  VoidCallback? onSettle;

  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _last = Offset.zero;
  VelocityTracker? _tracker;
  bool _locked = false;
  bool _accepted = false;

  @override
  String get debugDescription => 'row drag';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    if (_pointer != null) return;
    _pointer = event.pointer;
    _origin = _last = event.position;
    _tracker = VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, event.position);
    _locked = _accepted = false;
    if (!(onStart?.call() ?? true)) {
      _pointer = null;
      resolve(GestureDisposition.rejected);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _tracker?.addPosition(event.timeStamp, event.position);
      _last = event.position;
      final delta = event.position - _origin;
      if (!_locked) {
        switch (lockAxis(delta.dx, delta.dy, SwipeFeel.axisSlop)) {
          case null:
            return;
          case Axis2.y:
            _settle();
            resolve(GestureDisposition.rejected);
            stopTrackingPointer(event.pointer);
            return;
          case Axis2.x:
            _locked = true;
            resolve(GestureDisposition.accepted);
        }
      }
      if (_accepted) onMove?.call(delta.dx);
    } else if (event is PointerUpEvent) {
      if (_accepted) {
        final dx = (_last - _origin).dx;
        final vx = _tracker?.getVelocity().pixelsPerSecond.dx ?? 0;
        _end();
        onRelease?.call(dx, vx);
      } else {
        _settle();
      }
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (_accepted) {
        final dx = (_last - _origin).dx;
        _end();
        onRelease?.call(dx, 0);
      } else {
        _settle();
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer != _pointer) return;
    _accepted = true;
    onLock?.call();
    onMove?.call((_last - _origin).dx);
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    // Another recognizer (a tap, the list's scroll) won before this became a drag.
    _settle();
    stopTrackingPointer(pointer);
  }

  void _end() {
    _pointer = null;
    _locked = _accepted = false;
  }

  void _settle() {
    if (_pointer == null) return;
    _pointer = null;
    _locked = _accepted = false;
    onSettle?.call();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

/// A row with swipe shortcuts (the web's `SwipeRow`, Task 12c): left reveals a red "Borrar", right
/// reveals "Editar" ("Pagado" on a pending row). The row follows the finger. Left never deletes by
/// itself: a long or fast swipe only opens Borrar and a tap on it deletes. Right, let go past 40 %
/// of its width (or flicked) Editar / Pagado runs; a shorter swipe leaves it open (tap it to run it,
/// tap anywhere else or scroll to close). Only one row is open at a time (a [SwipeScope] above).
///
/// Swipes are shortcuts only: the screen-reader actions of the row do the same. Under the system's
/// "remove animations" the row fades instead of moving.
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.child,
    required this.deleteLabel,
    this.onDelete,
    this.right,
    this.enter = false,
    this.onEntered,
    this.gap = 0,
  });

  final Widget child;

  /// "Borrar".
  final String deleteLabel;

  /// Swipe left. The row slides out and folds away first, then this runs.
  final VoidCallback? onDelete;

  /// Swipe right: Editar, or Pagado on a pending row.
  final SwipeRight? right;

  /// Slides in on mount (a row brought back by Deshacer).
  final bool enter;

  /// The slide-in is over.
  final VoidCallback? onEntered;

  /// Space below the row. It folds away with the row, so the rows under it slide up the whole way.
  final double gap;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow> with TickerProviderStateMixin {
  /// The row's offset in px (negative is left). Unbounded: springs drive it.
  late final AnimationController _x = AnimationController.unbounded(vsync: this);

  /// 0: unfolded; 1: folded away (height zero, transparent).
  late final AnimationController _fold = AnimationController(
    vsync: this,
    duration: SwipeFeel.collapse,
  );

  final _key = GlobalKey();
  SwipeGroup? _group;
  Side? _open;
  Side? _armed;
  bool _gone = false;
  bool _entering = false;
  double _width = 1;
  double _from = 0;
  bool _reduceMotion = false;

  bool get _hasLeft => widget.onDelete != null;
  bool get _hasRight => widget.right != null;

  @override
  void initState() {
    super.initState();
    _x.addListener(_changed);
    if (widget.enter) {
      _entering = true;
      _fold.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _group = SwipeScope.maybeOf(context);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _group?.closed(_close);
    _x.dispose();
    _fold.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _enter() async {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    _width = box?.size.width ?? _width;
    setState(() => _entering = false);
    if (_reduceMotion) {
      await _fold.animateTo(0, duration: SwipeFeel.fade);
    } else {
      _x.value = -_width;
      unawaited(_fold.animateTo(0, curve: Curves.easeOut));
      await Future<void>.delayed(SwipeFeel.collapse ~/ 2);
      if (!mounted) return;
      await _springTo(0, rowOut: true);
    }
    if (mounted) widget.onEntered?.call();
  }

  Future<void> _springTo(double to, {double velocity = 0, bool rowOut = false}) {
    if (_reduceMotion) {
      _x.value = to;
      return Future.value();
    }
    final spring = SpringDescription(
      mass: 1,
      stiffness: rowOut ? SwipeFeel.rowOutStiffness : SwipeFeel.rowStiffness,
      damping: rowOut ? SwipeFeel.rowOutDamping : SwipeFeel.rowDamping,
    );
    return _x
        .animateWith(
          SpringSimulation(
            spring,
            _x.value,
            to,
            velocity,
            tolerance: Tolerance(distance: rowOut ? 1 : 0.5, velocity: 0.5),
          ),
        )
        .orCancel
        .then((_) {
          // The spring stops within half a pixel of its target: rest exactly on it.
          if (mounted) _x.value = to;
        })
        .catchError((Object _) {
          // Another touch or spring took the row over.
        });
  }

  bool _contains(Offset globalPosition) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    return (Offset.zero & box.size).contains(box.globalToLocal(globalPosition));
  }

  void _close() {
    if (!mounted) return;
    setState(() {
      _open = null;
      _armed = null;
    });
    _group?.closed(_close);
    unawaited(_springTo(0));
  }

  void _opened(Side side, double velocity) {
    _group?.opened(_close, _contains);
    setState(() => _open = side);
    unawaited(
      _springTo(
        side == Side.left ? -SwipeFeel.rowActionWidth : SwipeFeel.rowActionWidth,
        velocity: velocity,
      ),
    );
  }

  double get _rest => switch (_open) {
    Side.left => -SwipeFeel.rowActionWidth,
    Side.right => SwipeFeel.rowActionWidth,
    null => 0,
  };

  /// Deletes: the row leaves to the left, folds away (the rows under it slide up), then goes.
  Future<void> _remove({double velocity = 0}) async {
    final onDelete = widget.onDelete;
    if (onDelete == null || _gone) return;
    setState(() {
      _gone = true;
      _open = null;
      _armed = null;
    });
    _group?.closed(_close);
    if (_reduceMotion) {
      await _fold.animateTo(1, duration: SwipeFeel.fade);
    } else {
      // Off it goes; the fold starts as it leaves the screen, not after the spring's tail.
      final gone = Completer<void>();
      void watch() {
        if (_x.value <= -_width * SwipeFeel.rowGoneAt && !gone.isCompleted) gone.complete();
      }

      _x.addListener(watch);
      final leaving = _springTo(-_width, velocity: velocity, rowOut: true);
      unawaited(leaving.then((_) => gone.isCompleted ? null : gone.complete()));
      await gone.future;
      _x.removeListener(watch);
      if (!mounted) return;
      await _fold.animateTo(1, curve: Curves.easeOut);
    }
    if (mounted) onDelete();
  }

  void _runRight({double velocity = 0}) {
    final right = widget.right;
    if (right == null) return;
    setState(() => _open = null);
    _group?.closed(_close);
    unawaited(_springTo(0, velocity: velocity));
    right.run();
  }

  // -- the drag ------------------------------------------------------------------------------

  bool _onStart() {
    if (_gone || _entering) return false;
    // A touch catches the row where it is (mid-spring too).
    _x.stop();
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    _width = box?.size.width ?? _width;
    _from = _x.value;
    _armed = null;
    return true;
  }

  void _onLock() {
    final group = _group;
    if (group != null) {
      // Another open row closes as soon as this one is dragged.
      group.pointerDown(_globalCenter());
    }
  }

  Offset _globalCenter() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
  }

  void _onMove(double dx) {
    final offset = rowOffset(
      start: _from,
      dx: dx,
      width: _width,
      factor: SwipeFeel.rubberBand,
      left: _hasLeft,
      right: _hasRight,
    );
    _x.value = offset;
    final side = armedSide(offset, _width, SwipeFeel.rowThreshold);
    final next = switch (side) {
      Side.left => null,
      Side.right when !_hasRight => null,
      _ => side,
    };
    if (next != _armed) {
      _armed = next;
      // A tick at the threshold, each way.
      context.feedback(FeedbackEvent.thresholdCrossed);
      setState(() {});
    }
  }

  void _onRelease(double dx, double vx) {
    final outcome = rowRelease(
      offset: _x.value,
      vx: vx,
      width: _width,
      threshold: SwipeFeel.rowThreshold,
      flick: SwipeFeel.flickVelocity,
      openWidth: SwipeFeel.rowActionWidth,
      left: _hasLeft,
      right: _hasRight,
    );
    _armed = null;
    switch (outcome) {
      case RowRelease.commitRight:
        _runRight(velocity: vx);
      case RowRelease.commitLeft:
        unawaited(_remove(velocity: vx));
      case RowRelease.openLeft:
        _opened(Side.left, vx);
      case RowRelease.openRight:
        _opened(Side.right, vx);
      case RowRelease.close:
        _close();
    }
  }

  // A tap or a scroll caught the row: it goes back to where it rests, open or closed.
  void _onSettle() {
    if (!_gone && _x.value != _rest) unawaited(_springTo(_rest));
  }

  Map<Type, GestureRecognizerFactory> get _gestures => {
    RowDragRecognizer: GestureRecognizerFactoryWithHandlers<RowDragRecognizer>(
      RowDragRecognizer.new,
      (recognizer) => recognizer
        ..onStart = _onStart
        ..onLock = _onLock
        ..onMove = _onMove
        ..onRelease = _onRelease
        ..onSettle = _onSettle,
    ),
  };

  // A drag (or a tap on an open row, which closes it) is never also a tap on the row.
  Widget _face(Widget child) {
    if (_open == null) return child;
    return Stack(
      children: [
        child,
        // The row is open: a tap on it closes it instead of opening it.
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close),
        ),
      ],
    );
  }

  Widget _action(BuildContext context, Side side) {
    final colors = context.lkColors;
    final left = side == Side.left;
    final paid = !left && widget.right?.kind == SwipeRightKind.paid;
    final background = left ? colors.over : (paid ? colors.good : colors.brand);
    final foreground = left ? colors.bg : (paid ? colors.bg : colors.onBrand);
    final label = left ? widget.deleteLabel : widget.right!.label;
    final glyph = left ? '🗑' : (paid ? '✓' : '✎');
    final armed = _armed == side;
    return Positioned.fill(
      // `.lk-swipe-side`: its own rounded corners, clipped to them.
      child: ClipRRect(
        borderRadius: LkSurface.radius(LkRadius.lg),
        child: ColoredBox(
          color: background,
          child: Align(
            alignment: left ? Alignment.centerRight : Alignment.centerLeft,
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: label,
              onTap: _open == side ? (left ? _remove : _runRight) : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _open == side ? (left ? _remove : _runRight) : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: SwipeFeel.rowActionWidth,
                    minHeight: 44,
                  ),
                  child: SizedBox(
                    width: SwipeFeel.rowActionWidth,
                    height: double.infinity,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 2,
                      children: [
                        AnimatedScale(
                          // Past the threshold the action pops: on the right, letting go now runs it; on the left, it
                          // opens Borrar.
                          scale: armed ? 1.35 : 1,
                          duration: _reduceMotion ? Duration.zero : WambitoTokens.durationPress,
                          curve: Curves.ease,
                          child: Text(glyph, style: LkText.swipeGlyph.copyWith(color: foreground)),
                        ),
                        BlinkLine(
                          style: LkText.swipeAction,
                          child: Text(
                            LkText.upperCase(label),
                            style: LkText.swipeAction.copyWith(color: foreground),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offset = _x.value;
    final fold = _fold.value;
    final interactive = _hasLeft || _hasRight;
    // The face moves over the actions and is not clipped (`.lk-swipe` has no overflow): a row
    // swiped open reaches past its own edge.
    final l10n = AppLocalizations.of(context);
    Widget body = Stack(
      key: _key,
      clipBehavior: Clip.none,
      children: [
        // Each side shows only while the row is moved its way, so nothing peeks at rest.
        if (_hasLeft && offset < -0.5) _action(context, Side.left),
        if (_hasRight && offset > 0.5) _action(context, Side.right),
        Transform.translate(
          offset: Offset(offset, 0),
          child: SwipeHint(
            hint: !interactive
                ? null
                : (widget.right?.kind == SwipeRightKind.paid
                      ? l10n.swipeHintPending
                      : l10n.swipeHint),
            child: _face(widget.child),
          ),
        ),
      ],
    );
    if (interactive) {
      body = RawGestureDetector(gestures: _gestures, child: body);
    }
    // The screen reader's way to the same shortcuts.
    body = Semantics(
      customSemanticsActions: {
        if (_hasLeft) CustomSemanticsAction(label: widget.deleteLabel): _remove,
        if (_hasRight) CustomSemanticsAction(label: widget.right!.label): _runRight,
      },
      child: body,
    );
    return Visibility(
      visible: !_entering,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: false,
      child: Opacity(
        opacity: (1 - fold).clamp(0.0, 1.0),
        child: Align(
          heightFactor: _reduceMotion ? 1 : (1 - fold).clamp(0.0, 1.0),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.gap),
            child: body,
          ),
        ),
      ),
    );
  }
}
