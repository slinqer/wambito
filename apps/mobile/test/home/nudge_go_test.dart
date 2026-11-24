import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/bottom_bar.dart';
import 'package:wambito/ui/category_row.dart';

import '../budgets/budgets_test.dart' show pumpBudgets;
import '../budgets/fakes.dart';
import 'fakes.dart';
import 'fixtures.dart';

/// Home's menu "Categorías": on the web it opens the categories page, which the app has not; in the
/// app the categories are Categorías, a tab of home. So it must show that tab, with the categories
/// in view, not leave the top of home on screen with a thumb that moved somewhere below it.

FakeHomeRepository _noBudgets() => FakeHomeRepository(
  categoryList: [for (var i = 0; i < 12; i++) category('cat-$i', 'Categoría $i')],
  items: [tx('a', '2026-10-21', -18000, name: 'Mercado')],
);

void main() {
  for (final size in const [Size(412, 915), Size(360, 640)]) {
    testWidgets('on a ${size.width.toInt()} × ${size.height.toInt()} phone "Ir a Categorías" shows '
        'Categorías with the first category in view', (tester) async {
      final home = _noBudgets();
      await pumpBudgets(tester, home: home, budgets: FakeBudgetsRepository(home));
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.byType(CategoryRow), findsNothing, reason: 'Movimientos is showing');

      await _openCategories(tester);

      // The tab is Categorías, and the tabs' strip has come up to the top of the screen: what is
      // above it is scrolled away, the categories fill the screen.
      expect(find.byType(CategoryRow), findsWidgets);
      expect(find.text('Mercado'), findsNothing);
      expect(tester.getTopLeft(find.text('Categorías')).dy, lessThan(80));
      final first = tester.getRect(find.byType(CategoryRow).first);
      final bar = tester.getTopLeft(find.byType(BottomBar)).dy;
      expect(first.top, greaterThan(0));
      expect(first.bottom, lessThanOrEqualTo(bar), reason: 'the first category is above the bar');
    });
  }
}

/// Home's menu, then "Categorías".
Future<void> _openCategories(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home.account')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('home.categories')));
  await tester.pumpAndSettle();
}
