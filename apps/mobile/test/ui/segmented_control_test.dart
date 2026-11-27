import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/ui/segmented_control.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';
import '../support/feel.dart';

/// `SegmentedControl`'s behaviour, as apps/web/app/ui/SegmentedControl.tsx and its stories define
/// it. How it looks is test/parity/segmented_control_parity_test.dart's job.
class _Host extends StatefulWidget {
  const _Host({this.values = const ['budgets', 'transactions'], this.log});

  final List<String> values;
  final List<String>? log;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late var _value = widget.values.first;

  @override
  Widget build(BuildContext context) => SegmentedControl<String>(
    label: 'Vista',
    value: _value,
    options: [for (final v in widget.values) SegmentOption(v, v.toUpperCase())],
    onChanged: (v) {
      widget.log?.add(v);
      setState(() => _value = v);
    },
  );
}

bool _selected(WidgetTester t, String label) =>
    t.getSemantics(find.text(label)).flagsCollection.isSelected == Tristate.isTrue;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('tapping an option selects it', (t) async {
    final log = <String>[];
    final handle = t.ensureSemantics();
    await t.pumpWidget(uiApp(_Host(log: log)));
    expect(_selected(t, 'BUDGETS'), isTrue);
    await t.tap(find.text('TRANSACTIONS'));
    await t.pumpAndSettle();
    expect(log, ['transactions']);
    expect(_selected(t, 'TRANSACTIONS'), isTrue);
    expect(_selected(t, 'BUDGETS'), isFalse);
    handle.dispose();
  });

  testWidgets('arrows move the selection and wrap; Home and End jump to the ends', (t) async {
    final log = <String>[];
    await t.pumpWidget(uiApp(_Host(values: const ['a', 'b', 'c'], log: log)));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(log.last, 'c', reason: 'wraps from the first to the last');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(log, ['c', 'a'], reason: 'and from the last to the first');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(log.last, 'b');
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    expect(log.last, 'c');
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await t.pump();
    expect(log.last, 'a');
  });

  testWidgets('the moved-to option takes the focus, so the next key goes on from it', (t) async {
    final log = <String>[];
    await t.pumpWidget(uiApp(_Host(values: const ['a', 'b', 'c'], log: log)));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(log, ['b', 'c']);
  });

  testWidgets('only the selected option is in the tab order', (t) async {
    await t.pumpWidget(uiApp(_Host(values: const ['a', 'b', 'c'])));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    final first = FocusManager.instance.primaryFocus;
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(FocusManager.instance.primaryFocus, first, reason: 'Tab has nowhere else to go');
  });

  testWidgets('the list is a tab bar named by label; the options are tabs of at least 44px', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(uiApp(const _Host()));
    expect(t.getSemantics(find.bySemanticsLabel('Vista')).label, 'Vista');
    // 3px of padding either side of a 44px tab.
    expect(t.getSize(find.byType(SegmentedControl<String>)).height, greaterThanOrEqualTo(44 + 6));
    handle.dispose();
  });

  testWidgets('with a pager position the thumb follows it, 3px apart', (t) async {
    final position = ValueNotifier<double>(0);
    await t.pumpWidget(
      uiApp(
        SegmentedControl<String>(
          label: 'Vista',
          value: 'a',
          position: position,
          options: const [SegmentOption('a', 'A'), SegmentOption('b', 'B')],
          onChanged: (_) {},
        ),
        width: 300,
      ),
    );
    Offset thumb() => t.getTopLeft(
      find
          .descendant(
            of: find.byType(SegmentedControl<String>),
            matching: find.byType(DecoratedBox),
          )
          .at(1),
    );
    final start = thumb();
    position.value = 0.5;
    await t.pump();
    final half = thumb();
    position.value = 1;
    await t.pump();
    final end = thumb();
    // 300 wide, 3px padding and a 3px gap: each option is (300 - 6 - 3) / 2 = 145.5 wide.
    expect(half.dx - start.dx, closeTo(0.5 * (145.5 + 3), 0.01));
    expect(end.dx - start.dx, closeTo(145.5 + 3, 0.01));
  });

  testWidgets(
    'picking another option slides and snaps; the selected one or a change from code is silent',
    (t) async {
      final platform = await pumpFelt(t, uiApp(_Host(log: [])));
      await t.tap(find.text('BUDGETS'));
      await t.pumpAndSettle();
      expect(platform.haptics, isEmpty, reason: 'already selected');
      await t.tap(find.text('TRANSACTIONS'));
      await t.pumpAndSettle();
      expect(feltEvents(platform), [FeedbackEvent.segmentChanged]);
    },
  );

  testWidgets('with vibration off, a switch is silent', (t) async {
    final platform = await pumpFelt(t, uiApp(_Host(log: [])), vibration: false);
    await t.tap(find.text('TRANSACTIONS'));
    await t.pumpAndSettle();
    expect(platform.haptics, isEmpty);
  });
}
