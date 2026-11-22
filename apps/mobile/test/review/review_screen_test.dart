import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/add/add_repository.dart';
import 'package:wambito/add/add_sheet.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/capture_auto/capture_platform.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/review/review_repository.dart';

import '../add/fakes.dart';
import '../capture_auto/fakes.dart';
import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../settings/harness.dart';
import 'fakes.dart';

/// The review inbox (`/review`, `/review/<id>`) in the whole app, against fakes of the server.
/// "Today" is whatever the app clock says; the rows' dates only need to be in one month.

class _Env {
  _Env(this.app, this.home, this.review, this.add, this.capture);

  final SettingsEnv app;
  final FakeHomeRepository home;
  final FakeReviewRepository review;
  final FakeAddRepository add;
  final FakeAutoCapturePlatform capture;

  ProviderContainer get container => app.container;
}

Future<_Env> _pump(
  WidgetTester tester, {
  String location = '/review',
  Locale locale = const Locale('es'),
  List<Transaction>? items,
}) async {
  final home = FakeHomeRepository(
    items:
        items ??
        [
          detected('d1', '2026-10-21', -1250000, name: 'Cafe Juan'),
          detected('d2', '2026-10-21', -3000000, name: 'Taxi', source: 'google_wallet'),
          tx('t1', '2026-10-20', -500000, name: 'Pan'),
        ],
  );
  final review = FakeReviewRepository(home);
  final add = FakeAddRepository(home);
  final capture = FakeAutoCapturePlatform();
  final app = await pumpSettingsApp(
    tester,
    homeRepo: home,
    locale: locale,
    location: location,
    overrides: [
      reviewRepositoryProvider.overrideWithValue(review),
      addRepositoryProvider.overrideWithValue(add),
      autoCapturePlatformProvider.overrideWithValue(capture),
    ],
  );
  return _Env(app, home, review, add, capture);
}

void main() {
  testWidgets('lists what is waiting, each row marked with where it came from', (tester) async {
    await _pump(tester);
    expect(find.text('Por revisar'), findsWidgets);
    expect(find.text('Cafe Juan'), findsOneWidget);
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Pan'), findsNothing, reason: 'a confirmed one is not in the inbox');
    expect(find.text('por revisar · de Revolut'), findsOneWidget);
    expect(find.text('por revisar · de Google Wallet'), findsOneWidget);
  });

  testWidgets('Bien confirms that one: its row goes and the server is asked once', (tester) async {
    final env = await _pump(tester);
    await tester.tap(find.byKey(const Key('review.ok.d1')));
    await tester.pumpAndSettle();
    expect(env.review.calls, contains('confirm d1'));
    expect(find.text('Cafe Juan'), findsNothing);
    expect(find.text('Taxi'), findsOneWidget);
  });

  testWidgets('Bien takes away the phone notification of that one', (tester) async {
    final env = await _pump(tester);
    await tester.tap(find.byKey(const Key('review.ok.d1')));
    await tester.pumpAndSettle();
    expect(env.capture.callsNamed('dismiss'), ['dismiss d1']);
  });

  testWidgets('Confirmar todos takes away the notifications of every batch', (tester) async {
    final env = await _pump(
      tester,
      items: [for (var i = 0; i < 60; i++) detected('d$i', '2026-10-21', -100000, name: 'Shop $i')],
    );
    await tester.tap(find.byKey(const Key('review.confirmAll')));
    await tester.pumpAndSettle();
    final dismissed = env.capture.callsNamed('dismiss');
    expect([for (final c in dismissed) c.substring('dismiss '.length).split(',').length], [50, 10]);
  });

  testWidgets('a failed confirm keeps the notifications', (tester) async {
    final env = await _pump(tester);
    env.review.failures['confirm'] = const HomeFailure(0);
    await tester.tap(find.byKey(const Key('review.confirmAll')));
    await tester.pumpAndSettle();
    expect(env.capture.callsNamed('dismiss'), isEmpty);
  });

  testWidgets('each read of the inbox keeps only the notifications still waiting', (tester) async {
    final started = DateTime.now();
    final env = await _pump(tester);
    expect(env.capture.callsNamed('keepOnly').last.split(' ').last.split(',').toSet(), {
      'd1',
      'd2',
    });
    expect(
      env.capture.keepBefore.last.isBefore(started),
      isFalse,
      reason: 'the time the read started',
    );
  });

  testWidgets('an inbox read in full pages keeps every notification', (tester) async {
    final env = await _pump(
      tester,
      items: [
        for (var i = 0; i < reviewPageSize; i++)
          detected('d$i', '2026-10-21', -100000, name: 'Shop $i'),
      ],
    );
    expect(
      env.capture.callsNamed('keepOnly'),
      isEmpty,
      reason: 'a full page may leave older ones out: their notifications stay',
    );
  });

  testWidgets('Confirmar todos sends every id in one request', (tester) async {
    final env = await _pump(tester);
    await tester.tap(find.byKey(const Key('review.confirmAll')));
    await tester.pumpAndSettle();
    final sent = env.review.calls.where((c) => c.startsWith('confirm')).toList();
    expect(sent, hasLength(1));
    expect(sent.single.substring('confirm '.length).split(',').toSet(), {'d1', 'd2'});
    expect(find.text('Nada por revisar'), findsOneWidget);
    expect(find.byKey(const Key('review.confirmAll')), findsNothing);
  });

  testWidgets('Confirmar todos with more than 50 waiting sends them 50 at a time', (tester) async {
    final env = await _pump(
      tester,
      items: [for (var i = 0; i < 73; i++) detected('d$i', '2026-10-21', -100000, name: 'Shop $i')],
    );
    await tester.tap(find.byKey(const Key('review.confirmAll')));
    await tester.pumpAndSettle();
    final sent = env.review.calls.where((c) => c.startsWith('confirm')).toList();
    expect([for (final c in sent) c.substring('confirm '.length).split(',').length], [50, 23]);
    expect(find.text('Nada por revisar'), findsOneWidget);
  });

  testWidgets('when the second batch fails, the first one stays confirmed', (tester) async {
    final env = await _pump(
      tester,
      items: [for (var i = 0; i < 60; i++) detected('d$i', '2026-10-21', -100000, name: 'Shop $i')],
    );
    var confirms = 0;
    env.review.beforeConfirm = () {
      if (++confirms == 2) throw const HomeFailure(0);
    };
    await tester.tap(find.byKey(const Key('review.confirmAll')));
    await tester.pumpAndSettle();
    expect(env.home.items.where((t) => t.needsReview), hasLength(10));
    expect(find.byKey(const Key('review.confirmAll')), findsOneWidget);
  });

  testWidgets('a failed confirm keeps the rows and says so', (tester) async {
    final env = await _pump(tester);
    env.review.failures['confirm'] = const HomeFailure(0);
    await tester.tap(find.byKey(const Key('review.confirmAll')));
    await tester.pumpAndSettle();
    expect(find.text('Cafe Juan'), findsOneWidget);
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.byKey(const Key('review.confirmAll')), findsOneWidget);
  });

  testWidgets('with nothing waiting it says so', (tester) async {
    await _pump(tester, items: [tx('t1', '2026-10-20', -500000, name: 'Pan')]);
    expect(find.text('Nada por revisar'), findsOneWidget);
    expect(find.byKey(const Key('review.confirmAll')), findsNothing);
  });

  testWidgets('/review/<id> opens that one in the editor', (tester) async {
    await _pump(tester, location: '/review/d2');
    expect(find.byType(AddSheet), findsOneWidget);
    expect(find.text('Taxi'), findsWidgets);
  });

  testWidgets('/review/<id> of one detected after the inbox was read still opens it', (
    tester,
  ) async {
    final env = await _pump(tester);
    env.home.items.add(detected('d9', '2026-10-21', -800000, name: 'Panaderia'));
    env.app.router.go('/review/d9');
    await tester.pumpAndSettle();
    expect(find.byType(AddSheet), findsOneWidget);
    expect(find.text('Panaderia'), findsWidgets);
  });

  testWidgets('/review/<id> of one already confirmed just shows the inbox', (tester) async {
    await _pump(tester, location: '/review/t1');
    expect(find.byType(AddSheet), findsNothing);
    expect(find.text('Cafe Juan'), findsOneWidget);
  });

  testWidgets('Cambiar edits the row and saving confirms it in the same request', (tester) async {
    final env = await _pump(tester);
    await tester.tap(find.byKey(const Key('review.change.d1')));
    await tester.pumpAndSettle();
    expect(find.byType(AddSheet), findsOneWidget);
    // Typing a new name is the edit; Guardar sends it with needsReview false.
    await tester.enterText(find.byKey(const Key('add.name')), 'Cafe Pedro');
    await tester.pump();
    await tester.tap(find.byKey(const Key('add.save')));
    await tester.pumpAndSettle();
    final update = env.add.calls.singleWhere((c) => c.startsWith('update d1'));
    expect(update, contains('needsReview: false'));
    expect(update, contains('Cafe Pedro'));
    expect(find.text('Cafe Pedro'), findsNothing, reason: 'it left the inbox');
    expect(env.review.calls.last, 'pending', reason: 'the inbox read again');
    expect(
      env.capture.callsNamed('keepOnly').last,
      'keepOnly d2',
      reason: 'the read after the save takes its notification away',
    );
  });

  testWidgets('saving a row of the inbox with no change still confirms it', (tester) async {
    final env = await _pump(tester);
    await tester.tap(find.byKey(const Key('review.change.d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add.save')));
    await tester.pumpAndSettle();
    expect(env.add.calls.singleWhere((c) => c.startsWith('update d1')), contains('needsReview'));
    expect(find.text('Cafe Juan'), findsNothing);
  });

  testWidgets('in English', (tester) async {
    await _pump(tester, locale: const Locale('en'));
    expect(find.text('to review · from Revolut'), findsOneWidget);
    expect(find.text('CONFIRM ALL'), findsOneWidget);
  });
}
