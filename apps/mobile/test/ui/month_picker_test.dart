import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/ui/month_picker.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';
import '../support/feel.dart';

/// `MonthPicker`'s behaviour, as apps/web/app/ui/MonthPicker.tsx and its stories define it. How it
/// looks is test/parity/month_picker_parity_test.dart's job.
class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.log});

  final String initial;
  final List<String> log;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late var _month = widget.initial;

  @override
  Widget build(BuildContext context) => MonthPicker(
    month: _month,
    max: '2026-10',
    onChange: (next) {
      widget.log.add(next);
      setState(() => _month = next);
    },
  );
}

Finder _previous() => find.bySemanticsLabel('Mes anterior');
Finder _next() => find.bySemanticsLabel('Mes siguiente');

void main() {
  setUpAll(loadAppFonts);

  testWidgets('‹ and › raise onChange with the previous and the next month', (t) async {
    final log = <String>[];
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      uiApp(
        Row(
          children: [_Host(initial: '2026-10', log: log)],
        ),
      ),
    );
    expect(find.text('Octubre'), findsOneWidget);
    await t.tap(_previous());
    await t.pumpAndSettle();
    expect(log.last, '2026-09');
    expect(find.text('Septiembre'), findsOneWidget);
    await t.tap(_next());
    await t.pumpAndSettle();
    expect(log.last, '2026-10');
    expect(log, ['2026-09', '2026-10']);
    handle.dispose();
  });

  testWidgets('"next" stops at max: it is disabled there and raises nothing', (t) async {
    final log = <String>[];
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      uiApp(
        Row(
          children: [_Host(initial: '2026-10', log: log)],
        ),
      ),
    );
    expect(t.getSemantics(_next()).flagsCollection.isEnabled, Tristate.isFalse);
    await t.tap(_next(), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(log, isEmpty);
    handle.dispose();
  });

  testWidgets('months of another year than max carry the year; stepping crosses years', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      uiApp(
        Row(
          children: [_Host(initial: '2026-01', log: log)],
        ),
      ),
    );
    expect(find.text('Enero'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Mes anterior'));
    await t.pumpAndSettle();
    expect(log.last, '2025-12');
    expect(find.text('Diciembre 2025'), findsOneWidget);
  });

  testWidgets('English: "November 2025" and its arrows', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      uiApp(
        Row(
          children: [_Host(initial: '2025-11', log: log)],
        ),
        locale: const Locale('en'),
      ),
    );
    expect(find.text('November 2025'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Next month'));
    await t.pumpAndSettle();
    expect(find.text('December 2025'), findsOneWidget);
  });

  testWidgets('Enter on the focused arrow steps, and the name is a polite live region', (t) async {
    final log = <String>[];
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      uiApp(
        Row(
          children: [_Host(initial: '2026-10', log: log)],
        ),
      ),
    );
    expect(t.getSemantics(find.text('Octubre')).flagsCollection.isLiveRegion, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(log, ['2026-09']);
    handle.dispose();
  });

  test('addMonths steps over the end of a year, both ways', () {
    expect(addMonths('2026-01', -1), '2025-12');
    expect(addMonths('2025-12', 1), '2026-01');
    expect(addMonths('2026-10', 0), '2026-10');
    expect(addMonths('2026-10', -10), '2025-12');
    expect(addMonths('2026-10', 15), '2028-01');
  });

  testWidgets('a long month name at 130% font size does not overflow a 360px phone', (t) async {
    await t.pumpWidget(
      uiApp(
        Row(
          children: [_Host(initial: '2025-09', log: [])],
        ),
        width: 360,
        textScale: 1.3,
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('each month moved is one page turned', (t) async {
    final platform = await pumpFelt(
      t,
      uiApp(
        Row(
          children: [_Host(initial: '2026-10', log: [])],
        ),
      ),
    );
    await t.tap(_previous());
    await t.pumpAndSettle();
    await t.tap(_previous());
    await t.pumpAndSettle();
    expect(feltEvents(platform), [FeedbackEvent.pageChanged, FeedbackEvent.pageChanged]);
  });
}
