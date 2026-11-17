import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_cache.dart' show sessionOwnerOf;
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/offline/pending_saves.dart';

import '../add/fakes.dart';
import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../home/home_harness.dart';

/// A queue left on the phone by an earlier run: one movement, "Pan", saved with no network.
FakePendingSavesStore _leftOver() => FakePendingSavesStore()
  ..value = jsonEncode({
    'v': 1,
    'owner': sessionOwnerOf('t1'),
    'saves': [
      PendingSave(
        key: 'k1',
        batch: false,
        items: [
          CreateTransaction(
            (b) => b
              ..name = 'Pan'
              ..amount = -300000
              ..categoryId = 'cat-groceries'
              ..date = '2026-10-22'
              ..status = CreateTransactionStatusEnum.paid
              ..source_ = CreateTransactionSource_Enum.app,
          ),
        ],
      ).toJson(),
    ],
  });

FakeHomeRepository _server() => FakeHomeRepository(
  categoryList: [category('cat-groceries', 'Supermercado', icon: '🛒')],
  items: [tx('coffee', '2026-10-21', -450000, name: 'Café', categoryId: 'cat-groceries')],
);

/// Retries late enough that settling the first frames never reaches one.
final _retryIn30s = pendingRetryDelayProvider.overrideWithValue((_) => const Duration(seconds: 30));

void main() {
  testWidgets(
    'a save left from before shows with the cloud, and goes up when the network answers',
    (tester) async {
      final server = _server();
      // The first try finds no network; the next one hangs until the test lets it through.
      final add = FakeAddRepository(server)
        ..failures['create'] = const HomeFailure(0)
        ..hold = Completer<void>();
      await pumpHome(
        tester,
        server,
        addRepo: add,
        pendingStore: _leftOver(),
        overrides: [_retryIn30s],
      );

      // Still no answer: the row is there, marked as not uploaded, and nothing else changed.
      expect(find.text('Pan'), findsOneWidget);
      expect(find.byKey(const Key('row.unsent')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Pan')).dy,
        lessThan(tester.getTopLeft(find.text('Café')).dy),
        reason: 'the newest first',
      );

      // The network answers: the retry gets through, with the same key.
      add.hold!.complete();
      await tester.pumpAndSettle();
      expect(add.keys, ['k1', 'k1']);
      expect(server.items.where((t) => t.name == 'Pan'), hasLength(1));
      expect(find.text('Pan'), findsOneWidget);
      expect(find.byKey(const Key('row.unsent')), findsNothing);
      expect(find.text('Ya subimos el movimiento que anotaste sin conexión.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a save the server refuses is dropped, and home names it', (tester) async {
    final server = _server();
    final add = FakeAddRepository(server)
      ..failures['create'] = const HomeFailure(422, code: 'category_not_found');
    await pumpHome(tester, server, addRepo: add, pendingStore: _leftOver());

    expect(find.text('Pan'), findsNothing);
    expect(find.byKey(const Key('row.unsent')), findsNothing);
    expect(find.text('No pudimos guardar «Pan». Anótalo otra vez.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
  });

  testWidgets('a row not uploaded is read out as such', (tester) async {
    final server = _server();
    final add = FakeAddRepository(server)
      ..failures['create'] = const HomeFailure(0)
      ..hold = Completer<void>();
    final handle = tester.ensureSemantics();
    await pumpHome(
      tester,
      server,
      addRepo: add,
      pendingStore: _leftOver(),
      overrides: [_retryIn30s],
    );
    expect(find.bySemanticsLabel(RegExp('^Pan .* Sin subir\$')), findsOneWidget);
    handle.dispose();
    // Lets the retry find the network.
    add.hold!.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
  });

  group('a row not uploaded yet', () {
    /// Home with "Pan" waiting, and a network that does not answer until the test says so.
    Future<({FakeHomeRepository server, FakeAddRepository add})> waiting(
      WidgetTester tester,
    ) async {
      final server = _server();
      final add = FakeAddRepository(server)
        ..failures['create'] = const HomeFailure(0)
        ..hold = Completer<void>();
      await pumpHome(
        tester,
        server,
        addRepo: add,
        pendingStore: _leftOver(),
        overrides: [_retryIn30s],
      );
      return (server: server, add: add);
    }

    Future<void> letTimersEnd(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
    }

    testWidgets('a tap opens it to edit; the change shows at once and goes up after it', (
      tester,
    ) async {
      final env = await waiting(tester);
      await tester.tap(find.text('Pan'));
      await tester.pumpAndSettle();
      expect(find.text('Editar movimiento'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('add.name')), 'Pan integral');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add.save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add.sheet')), findsNothing);
      expect(find.text('Cambios guardados: Pan integral'), findsOneWidget);
      expect(env.add.calls.where((c) => c.startsWith('update')), isEmpty, reason: 'no network');
      expect(find.text('Pan integral'), findsOneWidget);
      expect(find.byKey(const Key('row.unsent')), findsOneWidget);

      // The network answers: the save goes up as it was, then the edit.
      env.add.hold!.complete();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(
        env.add.calls.where((c) => !c.startsWith('suggestions')).last,
        startsWith('update new-1'),
      );
      expect(env.server.items.where((t) => t.name == 'Pan integral'), hasLength(1));
      expect(find.text('Pan integral'), findsOneWidget);
      expect(find.byKey(const Key('row.unsent')), findsNothing);
      await letTimersEnd(tester);
    });

    testWidgets('a swipe left and Borrar delete it, and Deshacer brings it back', (tester) async {
      final env = await waiting(tester);
      await tester.timedDrag(
        find.text('Pan'),
        const Offset(-250, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pan'), findsOneWidget, reason: 'the swipe only opens Borrar');
      await tester.tap(find.text('BORRAR'));
      await tester.pumpAndSettle();
      expect(find.text('Pan'), findsNothing);
      expect(find.text('Eliminado: Pan'), findsOneWidget);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.text('Pan'), findsOneWidget);
      expect(find.text('De vuelta: Pan'), findsOneWidget);
      expect(env.server.calls.where((c) => c.startsWith('delete')), isEmpty);

      env.add.hold!.complete();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(env.server.items.where((t) => t.name == 'Pan'), hasLength(1));
      await letTimersEnd(tester);
    });

    testWidgets('deleted, it is deleted on the server too once it goes up', (tester) async {
      final env = await waiting(tester);
      await tester.timedDrag(
        find.text('Pan'),
        const Offset(-250, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('BORRAR'));
      await tester.pumpAndSettle();
      await letTimersEnd(tester);

      env.add.hold!.complete();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(env.server.items.where((t) => t.name == 'Pan'), isEmpty);
      expect(env.server.deleted.map((t) => t.name), ['Pan']);
      expect(find.text('Pan'), findsNothing);
      await letTimersEnd(tester);
    });
  });
}
