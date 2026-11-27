// Moving to another month keeps the month on screen until the next one has arrived: only the
// figures change, nothing blinks through the loading state.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/home/home_widgets.dart';

import 'home_harness.dart';

void main() {
  testWidgets('while the previous month loads, the current one stays on screen', (t) async {
    final repo = monthWithBudgets();
    await pumpHome(t, repo);
    expect(find.byType(HomeHero), findsOneWidget);

    final hold = Completer<void>();
    repo.holdSummary = hold;
    await t.tap(find.bySemanticsLabel('Mes anterior'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    expect(find.byType(HomeHeroPlaceholder), findsNothing, reason: 'no loading flash');
    expect(find.byType(HomeHero), findsOneWidget);

    hold.complete();
    repo.holdSummary = null;
    await t.pumpAndSettle();
    expect(find.byType(HomeHero), findsOneWidget);
  });
}
