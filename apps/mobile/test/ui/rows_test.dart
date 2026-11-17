import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/budget_bar.dart';
import 'package:wambito/ui/category_row.dart';
import 'package:wambito/ui/swipe_row.dart';
import 'package:wambito/ui/transaction_row.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';

/// `TransactionRow`'s, `CategoryRow`'s and `SwipeRow`'s presentation behaviour, as the web's
/// components and stories define it (the swipe gestures are test/ui/swipe_rules_test.dart's and the
/// home screen's). How they look is test/parity's job.
TransactionRow _tx({
  String name = 'continente',
  int amount = -608,
  TransactionRowStatus status = TransactionRowStatus.paid,
  VoidCallback? onOpen,
  Future<void> Function()? onPay,
  bool paidHere = false,
  String category = 'Supermercado',
}) => TransactionRow(
  name: name,
  categoryName: category,
  glyph: '🛒',
  amount: amount,
  currency: 'EUR',
  status: status,
  onOpen: onOpen ?? () {},
  onPay: onPay,
  paidHere: paidHere,
);

CategoryRow _category({
  int? budget = 18000,
  int spent = 19412,
  int? remaining = -1412,
  BudgetState state = BudgetState.over,
  String name = 'Supermercado',
  String? note,
  VoidCallback? onOpen,
}) => CategoryRow(
  name: name,
  note: note,
  glyph: '🛒',
  tint: const Color(0xFF4A2140),
  budget: budget,
  spent: spent,
  remaining: remaining,
  state: state,
  currency: 'EUR',
  onOpen: onOpen ?? () {},
);

void main() {
  setUpAll(loadAppFonts);

  group('TransactionRow', () {
    testWidgets('an expense: name, category and the amount with a real minus; the row opens', (
      t,
    ) async {
      var opened = 0;
      await t.pumpWidget(uiApp(SizedBox(width: 360, child: _tx(onOpen: () => opened++))));
      expect(find.text('continente'), findsOneWidget);
      expect(find.text('−6,08\u00a0€'), findsOneWidget);
      await t.tap(find.text('continente'));
      expect(opened, 1);
      expect(find.text('PENDIENTE'), findsNothing);
    });

    testWidgets('without a name it is titled with its category', (t) async {
      await t.pumpWidget(uiApp(SizedBox(width: 360, child: _tx(name: '  '))));
      expect(find.text('Supermercado'), findsNWidgets(2));
    });

    testWidgets('income shows a plus sign in good', (t) async {
      await t.pumpWidget(uiApp(SizedBox(width: 360, child: _tx(amount: 120000))));
      final text = t.widget<Text>(find.text('+1200,00\u00a0€'));
      expect(text.style!.color, const Color(0xFF7CFFB2));
    });

    testWidgets('a pending row pays from its badge, never opening the editor; the rest opens it', (
      t,
    ) async {
      var opened = 0, paid = 0;
      await t.pumpWidget(
        uiApp(
          SizedBox(
            width: 360,
            child: _tx(
              status: TransactionRowStatus.pending,
              onOpen: () => opened++,
              onPay: () async => paid++,
            ),
          ),
        ),
      );
      await t.tap(find.text('PENDIENTE'));
      await t.pumpAndSettle();
      expect(paid, 1);
      expect(opened, 0);
      expect(find.text('PAGADO'), findsOneWidget);
      await t.tap(find.text('continente'));
      expect(opened, 1);
    });

    testWidgets(
      'the badge is a 44px target in a 20px line, and tapping above its pill still pays',
      (t) async {
        var paid = 0;
        await t.pumpWidget(
          uiApp(
            SizedBox(
              width: 360,
              child: _tx(status: TransactionRowStatus.pending, onPay: () async => paid++),
            ),
          ),
        );
        final pill = t.getRect(find.text('PENDIENTE'));
        await t.tapAt(Offset(pill.center.dx, pill.top - 8));
        await t.pumpAndSettle();
        expect(paid, 1);
      },
    );

    testWidgets('pending without a way to pay it shows a plain label, not a button', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        uiApp(SizedBox(width: 360, child: _tx(status: TransactionRowStatus.pending))),
      );
      expect(find.text('PENDIENTE'), findsOneWidget);
      expect(find.bySemanticsLabel('Pendiente, marcar como pagado'), findsNothing);
      handle.dispose();
    });

    testWidgets('paid from this row just now, the badge stays showing "✓ Pagado"', (t) async {
      await t.pumpWidget(
        uiApp(SizedBox(width: 360, child: _tx(paidHere: true, onPay: () async {}))),
      );
      expect(find.text('PAGADO'), findsOneWidget);
    });

    testWidgets('Tab reaches the row, then its badge', (t) async {
      var opened = 0, paid = 0;
      await t.pumpWidget(
        uiApp(
          SizedBox(
            width: 360,
            child: _tx(
              status: TransactionRowStatus.pending,
              onOpen: () => opened++,
              onPay: () async => paid++,
            ),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(paid, 1);
    });

    testWidgets(
      'the row is one button named by its name, amount and category; the badge stays its own',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          uiApp(
            SizedBox(
              width: 360,
              child: _tx(status: TransactionRowStatus.pending, onPay: () async {}),
            ),
          ),
        );
        expect(find.bySemanticsLabel('continente −6,08\u00a0€ Supermercado'), findsOneWidget);
        expect(find.bySemanticsLabel('Pendiente, marcar como pagado'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('a 40-character name is cut off, with no overflow, at 130% on a 360px phone', (
      t,
    ) async {
      await t.pumpWidget(
        uiApp(
          _tx(name: 'Supermercado, farmacia y cosas del hogar', amount: -150000000000),
          width: 360,
          textScale: 1.3,
        ),
      );
      expect(t.takeException(), isNull);
      expect(find.textContaining('Supermercado, farmacia'), findsOneWidget);
    });
  });

  group('CategoryRow', () {
    testWidgets('over budget the status says so in words, next to the budget and a bar', (t) async {
      var opened = 0;
      await t.pumpWidget(uiApp(SizedBox(width: 360, child: _category(onOpen: () => opened++))));
      final handle = t.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp(r'^Supermercado Te pasaste 14,12\s€$')), findsOneWidget);
      handle.dispose();
      expect(find.text('180,00\u00a0€'), findsOneWidget);
      expect(find.byType(BudgetBar), findsOneWidget);
      await t.tap(find.text('Supermercado'));
      expect(opened, 1);
    });

    testWidgets(
      'near and within budget say "Quedan"; without a budget: no budget, what was spent, no bar',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          uiApp(
            SizedBox(
              width: 360,
              child: Column(
                children: [
                  _category(budget: 30000, spent: 25367, remaining: 4633, state: BudgetState.near),
                  _category(
                    name: 'Regalos',
                    budget: null,
                    spent: 2500,
                    remaining: null,
                    state: BudgetState.ok,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.bySemanticsLabel(RegExp(r'^Supermercado Quedan 46,33\s€$')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(r'^Regalos Sin presupuesto$')), findsOneWidget);
        expect(find.byType(BudgetBar), findsOneWidget, reason: 'only the one with a budget');
        handle.dispose();
      },
    );

    testWidgets('an archived category carries its note in its name', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(uiApp(SizedBox(width: 360, child: _category(note: 'archivada'))));
      expect(find.bySemanticsLabel(RegExp(r'^Supermercado archivada Te pasaste')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a 40-character name and a huge budget, at 130% on 360px: no overflow', (t) async {
      await t.pumpWidget(
        uiApp(
          _category(
            name: 'Supermercado, farmacia y cosas del hogar',
            budget: 150000000000,
            spent: 120000000000,
            remaining: 30000000000,
            state: BudgetState.near,
          ),
          width: 360,
          textScale: 1.3,
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('SwipeRow', () {
    Widget row({bool pending = false}) => uiApp(
      SizedBox(
        width: 360,
        child: SwipeRow(
          deleteLabel: 'Borrar',
          onDelete: () {},
          right: SwipeRight(
            pending ? SwipeRightKind.paid : SwipeRightKind.edit,
            () {},
            pending ? 'Pagado' : 'Editar',
          ),
          child: _tx(status: pending ? TransactionRowStatus.pending : TransactionRowStatus.paid),
        ),
      ),
    );

    testWidgets('the row inside says what the swipes do, since screen readers take them over', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(row());
      final named = find.bySemanticsLabel(RegExp(r'^continente'));
      expect(t.getSemantics(named).getSemanticsData().hint, 'Tócalo para editarlo o borrarlo.');
      await t.pumpWidget(row(pending: true));
      expect(
        t.getSemantics(named).getSemanticsData().hint,
        'Tócalo para editarlo o borrarlo; Pendiente lo marca pagado.',
      );
      handle.dispose();
    });

    testWidgets('swiped open to the right the row reaches past its own edge, and Editar shows', (
      t,
    ) async {
      await t.pumpWidget(row());
      final rest = t.getRect(find.byType(TransactionRow));
      await t.timedDrag(
        find.byType(SwipeRow),
        const Offset(70, 0),
        const Duration(milliseconds: 300),
      );
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(TransactionRow)).left, closeTo(rest.left + 88, 0.5));
      expect(find.text('EDITAR'), findsOneWidget);
    });

    testWidgets('swiped left, Borrar shows in the delete colour', (t) async {
      await t.pumpWidget(row());
      await t.timedDrag(
        find.byType(SwipeRow),
        const Offset(-70, 0),
        const Duration(milliseconds: 300),
      );
      await t.pumpAndSettle();
      expect(find.text('BORRAR'), findsOneWidget);
      expect(t.widget<Text>(find.text('BORRAR')).style!.color, const Color(0xFF15122B));
    });

    testWidgets('a long fast swipe left leaves Borrar open and deletes nothing', (t) async {
      var deleted = 0;
      await t.pumpWidget(
        uiApp(
          SizedBox(
            width: 360,
            child: SwipeRow(
              deleteLabel: 'Borrar',
              onDelete: () => deleted++,
              right: SwipeRight(SwipeRightKind.edit, () {}, 'Editar'),
              child: _tx(status: TransactionRowStatus.paid),
            ),
          ),
        ),
      );
      await t.fling(find.byType(SwipeRow), const Offset(-300, 0), 2000);
      await t.pumpAndSettle();
      expect(find.text('BORRAR'), findsOneWidget);
      expect(deleted, 0);
      await t.tap(find.text('BORRAR'));
      await t.pumpAndSettle();
      expect(deleted, 1);
    });

    testWidgets('at rest neither action is in the tree', (t) async {
      await t.pumpWidget(row());
      expect(find.text('BORRAR'), findsNothing);
      expect(find.text('EDITAR'), findsNothing);
    });
  });
}
