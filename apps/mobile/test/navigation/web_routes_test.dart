import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/server_url.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/ui/bottom_bar.dart';
import 'package:wambito/ui/category_row.dart';
import 'package:wambito/ui/press_button.dart';

import '../budgets/budgets_test.dart' show pumpBudgets;
import '../budgets/fakes.dart';
import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../settings/harness.dart';

/// Every page of the web (apps/web/app/routes.ts) has its place in the app, and is reached the way
/// the web reaches it: the face menu (Recurrentes, Categorías, Ajustes), the home cards and the
/// links of Settings. There is no categories page: categories are managed in home's Categorías tab
/// (the founder's ruling), so wherever the web links to that page the app opens that tab.

String _location(SettingsEnv env) {
  final match = env.router.routerDelegate.currentConfiguration.last;
  return match.matchedLocation;
}

FakeHomeRepository _withMovements() => FakeHomeRepository(
  categoryList: [for (var i = 0; i < 12; i++) category('cat-$i', 'Categoría $i')],
  items: [tx('a', '2026-10-21', -18000, name: 'Mercado', categoryId: 'cat-0')],
);

/// The app with the budgets tab's repository too (the Categorías tab loads from it).
Future<SettingsEnv> _pumpWithBudgets(WidgetTester tester) async {
  final home = _withMovements();
  final env = await pumpBudgets(tester, home: home, budgets: FakeBudgetsRepository(home));
  return env.settings;
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  group('the face menu holds what the web\'s does', () {
    testWidgets('Recurrentes, Categorías and Ajustes, in the web\'s order', (tester) async {
      await pumpSettingsApp(tester, homeRepo: _withMovements());
      await openAccountMenu(tester);
      final keys = ['home.recurring', 'home.categories', 'home.settings'];
      final tops = [for (final k in keys) tester.getTopLeft(find.byKey(Key(k))).dy];
      expect(tops, orderedEquals([...tops]..sort()), reason: 'in that order, one under another');
      expect(find.byKey(const Key('home.saveProgress')), findsNothing);
    });

    testWidgets('a guest\'s Guarda tu progreso stays, before them', (tester) async {
      await pumpSettingsApp(tester, guest: true, homeRepo: _withMovements());
      await openAccountMenu(tester);
      expect(
        tester.getTopLeft(find.byKey(const Key('home.saveProgress'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('home.recurring'))).dy),
      );
    });

    testWidgets('in English they read as the web\'s', (tester) async {
      await pumpSettingsApp(tester, locale: const Locale('en'), homeRepo: _withMovements());
      await openAccountMenu(tester);
      for (final label in ['Recurring', 'Categories', 'Settings']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('Recurrentes opens /recurring and closes the menu', (tester) async {
      final env = await pumpSettingsApp(tester, homeRepo: _withMovements());
      await openAccountMenu(tester);
      await tester.tap(find.byKey(const Key('home.recurring')));
      await tester.pumpAndSettle();
      expect(_location(env), '/recurring');
      expect(find.byKey(const Key('recurring.page')), findsOneWidget);
      expect(find.text('Recurrentes'), findsWidgets);
      expect(find.byKey(const Key('home.recurring')), findsNothing, reason: 'the menu is closed');
      // Back goes to home.
      await tester.tap(find.text('INICIO'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('Categorías stays on home and shows its Categorías tab', (tester) async {
      final env = await _pumpWithBudgets(tester);
      expect(find.byType(CategoryRow), findsNothing, reason: 'Movimientos is showing');
      await openAccountMenu(tester);
      await tester.tap(find.byKey(const Key('home.categories')));
      await tester.pumpAndSettle();
      expect(_location(env), '/', reason: 'no categories page: the tab of home');
      expect(find.byType(CategoryRow), findsWidgets);
      expect(find.text('Mercado'), findsNothing);
      expect(find.byKey(const Key('home.categories')), findsNothing, reason: 'menu closed');
      expect(
        tester.getRect(find.byType(CategoryRow).first).bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(BottomBar)).dy),
      );
    });

    testWidgets('and again, after going back to Movimientos by hand', (tester) async {
      await _pumpWithBudgets(tester);
      for (var i = 0; i < 2; i++) {
        await openAccountMenu(tester);
        await tester.tap(find.byKey(const Key('home.categories')));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryRow), findsWidgets, reason: 'round $i');
        await tester.tap(find.text('Movimientos'));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryRow), findsNothing, reason: 'round $i');
      }
    });

    testWidgets('from a screen over home, Categorías goes back to home\'s tab', (tester) async {
      final env = await _pumpWithBudgets(tester);
      env.router.push<void>('/settings');
      await tester.pumpAndSettle();
      env.container.read(homeViewRequestProvider.notifier).show(HomeView.budgets);
      env.router.go('/');
      await tester.pumpAndSettle();
      expect(find.byType(CategoryRow), findsWidgets);
    });

    testWidgets('Ajustes still opens /settings', (tester) async {
      final env = await pumpSettingsApp(tester, homeRepo: _withMovements());
      await openAccountMenu(tester);
      await tester.tap(find.byKey(const Key('home.settings')));
      await tester.pumpAndSettle();
      expect(_location(env), '/settings');
    });
  });

  group('the routes', () {
    testWidgets('there is no /categories page: it lands on home\'s Categorías tab', (tester) async {
      final env = await _pumpWithBudgets(tester);
      expect(find.byType(CategoryRow), findsNothing, reason: 'Movimientos first');
      env.router.go('/categories');
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_location(env), '/');
      expect(find.byType(CategoryRow), findsWidgets, reason: 'the Categorías tab');
    });

    testWidgets('/categories/:id, /settings and /insights keep their places', (tester) async {
      final env = await pumpSettingsApp(tester, homeRepo: _withMovements());
      for (final path in ['/categories/cat-0', '/settings', '/insights']) {
        env.router.go(path);
        await tester.pumpAndSettle();
        expect(_location(env), path);
      }
    });

    testWidgets(
      '/recurring shows the web\'s page: back, title, the add button and the empty list',
      (tester) async {
        final env = await pumpSettingsApp(tester, homeRepo: _withMovements());
        env.router.go('/recurring');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('recurring.page')), findsOneWidget);
        expect(find.text('Recurrentes'), findsOneWidget);
        expect(find.text('INICIO'), findsOneWidget);
        expect(find.text('NUEVO RECURRENTE'), findsOneWidget);
        expect(
          tester.widget<PressButton>(find.byKey(const Key('recurring.add'))).onPressed,
          isNotNull,
          reason: 'the categories are in: the add button is on',
        );
        expect(find.textContaining('Aquí van tus pagos fijos'), findsOneWidget);
      },
    );

    testWidgets('/import shows the page\'s head: Wambito and "Trae tu historial"', (tester) async {
      final env = await pumpSettingsApp(tester, homeRepo: _withMovements());
      env.router.go('/import');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import.page')), findsOneWidget);
      expect(find.text('Trae tu historial'), findsOneWidget);
      expect(find.text('Trae tus movimientos de otra app.'), findsOneWidget);
    });

    for (final path in ['/welcome', '/welcome/currency', '/welcome/budgets']) {
      testWidgets('$path is not for an account that has finished the welcome: it goes home', (
        tester,
      ) async {
        final env = await pumpSettingsApp(tester, homeRepo: _withMovements());
        env.router.go(path);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('welcome.page')), findsNothing);
        expect(_location(env), '/');
      });
    }

    testWidgets('signed out, /recurring, /import and /welcome go to entry', (tester) async {
      final env = await pumpSettingsApp(tester, signedIn: false);
      for (final path in ['/recurring', '/import', '/welcome']) {
        env.router.go(path);
        await tester.pumpAndSettle();
        expect(_location(env), '/entry', reason: path);
      }
    });
  });

  group('the home cards', () {
    testWidgets('an account with no movements is offered the import, as the web does', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, homeRepo: FakeHomeRepository());
      expect(find.byKey(const Key('home.nudge.import')), findsOneWidget);
      await _nextNudge(tester);
      expect(find.text('Trae tu historial'), findsOneWidget);
      expect(
        find.text('Importa lo que llevas en Budge y empieza con tus números de verdad.'),
        findsOneWidget,
      );
      await tester.tap(find.text('TRAER MI HISTORIAL'));
      await tester.pumpAndSettle();
      expect(_location(env), '/import');
      expect(find.byKey(const Key('import.page')), findsOneWidget);
    });

    testWidgets('after the budgets card, side by side: a swipe shows the next one', (tester) async {
      await pumpSettingsApp(tester, homeRepo: FakeHomeRepository());
      final budgets = tester.getRect(find.byKey(const Key('home.nudge.budgets')));
      final import = tester.getRect(find.byKey(const Key('home.nudge.import')));
      expect(import.top, budgets.top, reason: 'one row, not one under the other');
      expect(import.left, greaterThanOrEqualTo(budgets.right), reason: 'to its right');
      final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(import.left, greaterThan(screen - 16), reason: 'only its edge peeks in');
      expect(find.byKey(const Key('home.nudges.dot.0')), findsOneWidget);
      expect(find.byKey(const Key('home.nudges.dot.1')), findsOneWidget);

      await _nextNudge(tester);
      final shown = tester.getRect(find.byKey(const Key('home.nudge.import')));
      expect(shown.left, closeTo(budgets.left, 1), reason: 'where the first one was');
    });

    testWidgets('a card has its words across it and its buttons under them', (tester) async {
      await pumpSettingsApp(tester, homeRepo: _withMovements());
      final card = find.byKey(const Key('home.nudge.budgets'));
      final lead = tester.getRect(
        find.text(
          'Así Wambito te avisa antes de que te pases. Toca una categoría y ponle un monto.',
        ),
      );
      final go = tester.getRect(find.text('IR A CATEGORÍAS'));
      final later = tester.getRect(
        find.bySemanticsLabel('Ahora no: Ponle presupuesto a tus categorías'),
      );
      expect(go.top, greaterThan(lead.bottom));
      expect(later.top, greaterThan(lead.bottom));
      expect(later.center.dy, closeTo(go.center.dy, 2), reason: 'side by side');
      expect(later.left, greaterThan(go.right));
      expect(lead.width, greaterThan(tester.getRect(card).width * 0.8), reason: 'the whole card');
      expect(find.byKey(const Key('home.nudges.dot.0')), findsNothing, reason: 'one card, no dots');
    });

    testWidgets('an account with movements has no import card', (tester) async {
      await pumpSettingsApp(tester, homeRepo: _withMovements());
      expect(find.byKey(const Key('home.nudge.budgets')), findsOneWidget);
      expect(find.byKey(const Key('home.nudge.import')), findsNothing);
    });

    testWidgets('movements in another month than the one on screen count too', (tester) async {
      final home = FakeHomeRepository(items: [tx('old', '2026-03-02', -500, name: 'Antiguo')]);
      await pumpSettingsApp(tester, homeRepo: home);
      expect(find.byKey(const Key('home.nudge.import')), findsNothing);
    });

    testWidgets('"Ahora no" puts it away for good, and the budgets card stays', (tester) async {
      final env = await pumpSettingsApp(tester, homeRepo: FakeHomeRepository());
      await _nextNudge(tester);
      await tester.tap(find.bySemanticsLabel('Ahora no: Trae tu historial'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home.nudge.import')), findsNothing);
      expect(find.byKey(const Key('home.nudge.budgets')), findsOneWidget);
      expect(env.flags.keys.any((k) => k.endsWith('.import')), isTrue);
    });

    testWidgets('no answer about the movements, no card', (tester) async {
      final home = FakeHomeRepository();
      home.failures['hasTransactions'] = Exception('offline');
      await pumpSettingsApp(tester, homeRepo: home);
      expect(find.byKey(const Key('home.nudge.import')), findsNothing);
    });

    testWidgets('in English', (tester) async {
      await pumpSettingsApp(tester, locale: const Locale('en'), homeRepo: FakeHomeRepository());
      await _nextNudge(tester);
      expect(find.text('Bring your history'), findsOneWidget);
      expect(find.text('BRING MY HISTORY'), findsOneWidget);
    });
  });

  group('Settings\' links', () {
    testWidgets('"Tus datos" leads to the import, as the web\'s Settings does', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await pumpSettingsApp(tester, location: '/settings/data');
      await _scrollTo(tester, find.byKey(const Key('settings.import')));
      expect(find.text('Importar movimientos'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('settings.import'))).hint,
        'Importa lo que llevas en Budge.',
      );
      await tester.tap(find.byKey(const Key('settings.import')));
      await tester.pumpAndSettle();
      expect(_location(env), '/import');
      expect(find.byKey(const Key('import.page')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('"Más en la web" is for the landing and the roadmap only', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      await _scrollTo(tester, find.byKey(const Key('settings.web')));
      expect(find.text('Abrir Wambito en la web'), findsOneWidget);
      expect(find.text('La página de Wambito y lo que viene.'), findsOneWidget);
      // The card names no page of the app (time and money, the passkeys and the import are cards of the
      // page itself now).
      expect(find.bySemanticsLabel(RegExp('recurrentes')), findsNothing);
      await tester.tap(find.byKey(const Key('settings.web')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byKey(const Key('settings.roadmap')));
      await tester.tap(find.byKey(const Key('settings.roadmap')));
      await tester.pumpAndSettle();
      expect(env.opener.opened, [defaultServerUrl, defaultServerUrl.resolve('/roadmap')]);
      handle.dispose();
    });

    testWidgets('in English they are the English pages', (tester) async {
      final env = await pumpSettingsApp(
        tester,
        locale: const Locale('en'),
        location: '/settings/more',
      );
      await _scrollTo(tester, find.byKey(const Key('settings.web')));
      await tester.tap(find.byKey(const Key('settings.web')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byKey(const Key('settings.roadmap')));
      await tester.tap(find.byKey(const Key('settings.roadmap')));
      await tester.pumpAndSettle();
      expect(env.opener.opened.map((u) => u.path), ['/en', '/en/roadmap']);
    });
  });
}

/// Swipes the home cards to the next one.
Future<void> _nextNudge(WidgetTester tester) async {
  await tester.fling(find.byKey(const Key('home.nudges')), const Offset(-300, 0), 1000);
  await tester.pumpAndSettle();
}
