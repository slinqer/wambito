// Swiping a row feels like turning a watch crown: a tick per notch, firmer toward the threshold,
// quieter on the way home, and one soft knock where it bounces.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/ui/lk_icons.dart';
import 'package:wambito/ui/swipe_row.dart';

import '../feedback/fakes.dart';
import '../support/feel.dart';
import '../support/ui_app.dart';

Widget _row({bool reduce = false}) => uiApp(
  SizedBox(
    width: 360,
    height: 64,
    child: SwipeRow(
      deleteLabel: 'Borrar',
      onDelete: () {},
      right: SwipeRight(SwipeRightKind.edit, () {}, 'Editar'),
      child: const ColoredBox(color: Color(0xFF222222), child: SizedBox.expand()),
    ),
  ),
  disableAnimations: reduce,
);

/// Drags the row by [dx] in [steps] moves, [gap] apart; the gesture's `up` should be sent with
/// [_end] so its time stamp follows the moves'.
Future<TestGesture> _drag(
  WidgetTester t,
  double dx, {
  int steps = 7,
  Duration gap = const Duration(milliseconds: 30),
}) async {
  final gesture = await t.startGesture(t.getCenter(find.byType(SwipeRow)));
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(dx / steps, 0), timeStamp: gap * (i + 1));
    await t.pump(gap);
  }
  _at = gap * (steps + 1);
  return gesture;
}

var _at = Duration.zero;

/// Lets go at the time after the last move.
Future<void> _end(TestGesture gesture) => gesture.up(timeStamp: _at);

List<double> _detentScales(FakeFeedbackPlatform platform) => [
  for (final p in platform.haptics)
    if (p.waveform.length == 1 && p.waveform.single == 12) p.primitives.single.scale,
];

void main() {
  testWidgets('dragging ticks once per notch, firmer as it goes', (t) async {
    final platform = await pumpFelt(t, _row());
    final gesture = await _drag(t, 70);
    final scales = _detentScales(platform);
    expect(scales.length, 3, reason: '20, 40 and 60 px (after the axis slop)');
    expect(scales, orderedEquals([...scales]..sort()));
    await _end(gesture);
    await t.pumpAndSettle();
  });

  testWidgets('a fast drag skips notches instead of buzzing', (t) async {
    final platform = await pumpFelt(t, _row());
    final gesture = await _drag(t, 70, gap: const Duration(milliseconds: 5));
    expect(_detentScales(platform).length, lessThan(3));
    await _end(gesture);
    await t.pumpAndSettle();
  });

  testWidgets('let go short, it rolls home through the notches and bounces once', (t) async {
    final platform = await pumpFelt(t, _row());
    final gesture = await _drag(t, 34, steps: 4);
    final before = platform.haptics.length;
    await _end(gesture);
    await t.pumpAndSettle();
    final after = platform.haptics.sublist(before);
    expect(after.where((p) => p == hapticPatterns[FeedbackEvent.swipeBounced]).length, 1);
    expect(after.any((p) => p.waveform.length == 1 && p.waveform.single == 12), isTrue);
  });

  testWidgets('Borrar left open neither rolls back nor bounces', (t) async {
    final platform = await pumpFelt(t, _row());
    final gesture = await _drag(t, -70);
    final before = platform.haptics.length;
    await _end(gesture);
    await t.pumpAndSettle();
    expect(find.text('BORRAR'), findsOneWidget);
    expect(
      platform.haptics.sublist(before),
      isNot(contains(hapticPatterns[FeedbackEvent.swipeBounced])),
    );
  });

  testWidgets('with reduced motion the row jumps home: no rolling, no bounce', (t) async {
    final platform = await pumpFelt(t, _row(reduce: true));
    final gesture = await _drag(t, 34, steps: 4);
    final before = platform.haptics.length;
    await _end(gesture);
    await t.pumpAndSettle();
    expect(platform.haptics.sublist(before), isEmpty);
  });

  testWidgets('the actions draw the app\'s icons, not emoji', (t) async {
    await pumpFelt(t, _row());
    final gesture = await _drag(t, -90);
    await _end(gesture);
    await t.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is LkIcon && w.name == LkIconName.trash),
      findsOneWidget,
    );
    expect(find.text('🗑'), findsNothing);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    final right = await _drag(t, 90);
    await _end(right);
    await t.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is LkIcon && w.name == LkIconName.pencil),
      findsOneWidget,
    );
    expect(find.text('✎'), findsNothing);
  });
}
