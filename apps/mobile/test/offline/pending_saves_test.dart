import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/add/save_outcome.dart' show canRetrySave;
import 'package:wambito/add/add_repository.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/capture/capture_repository.dart';
import 'package:wambito/home/home_cache.dart' show sessionOwnerOf;
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/offline/pending_saves.dart';

import '../add/fakes.dart';
import '../capture/fakes.dart';
import '../home/fakes.dart';

CreateTransaction _input(String name, int amount, {String date = '2026-10-22'}) =>
    CreateTransaction(
      (b) => b
        ..name = name
        ..amount = amount
        ..categoryId = 'cat-groceries'
        ..date = date
        ..status = CreateTransactionStatusEnum.paid
        ..source_ = CreateTransactionSource_Enum.app,
    );

class _Env {
  _Env(this.container, this.server, this.add, this.capture, this.store);

  final ProviderContainer container;
  final FakeHomeRepository server;
  final FakeAddRepository add;
  final FakeCaptureRepository capture;
  final FakePendingSavesStore store;

  PendingSaves get queue => container.read(pendingSavesProvider.notifier);
  PendingSavesState get state => container.read(pendingSavesProvider);
}

_Env _env({FakePendingSavesStore? store, String? token = 't1'}) {
  final server = FakeHomeRepository(items: []);
  final add = FakeAddRepository(server);
  final capture = FakeCaptureRepository(server);
  final kept = store ?? FakePendingSavesStore();
  final container = ProviderContainer(
    overrides: [
      addRepositoryProvider.overrideWithValue(add),
      homeRepositoryProvider.overrideWithValue(server),
      captureRepositoryProvider.overrideWithValue(capture),
      pendingSavesStoreProvider.overrideWithValue(kept),
      pendingSavesTokenProvider.overrideWithValue(token),
      // Long enough that no test sees a retry it did not ask for.
      pendingRetryDelayProvider.overrideWithValue((_) => const Duration(hours: 1)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(pendingSavesProvider, (_, _) {});
  return _Env(container, server, add, capture, kept);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a save waits on the phone, bound to the session, and goes up with its own key', () async {
    final env = _env();
    env.add.failures['create'] = const HomeFailure(0);
    await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));

    final doc = jsonDecode(env.store.value!) as Map<String, Object?>;
    expect(doc['v'], 1);
    expect(doc['owner'], sessionOwnerOf('t1'));
    expect((doc['saves']! as List).single, containsPair('key', 'k1'));

    // Still no network: it stays.
    await env.queue.send();
    expect(env.state.saves, hasLength(1));
    expect(env.state.notice, isNull);

    // The network is back.
    await env.queue.send();
    expect(env.add.keys, ['k1', 'k1']);
    expect(env.server.items.single.name, 'Pan');
    expect(env.state.saves, isEmpty);
    expect(env.state.notice!.sent, 1);
    await _settle();
    expect(env.store.value, isNull, reason: 'nothing left to keep');
  });

  test('saves go up oldest first; a batch goes up as one batch', () async {
    final env = _env();
    await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
    await env.queue.add(
      PendingSave(
        key: 'k2',
        items: [_input('Almuerzo', -1500000), _input('Uber', -300000)],
        batch: true,
      ),
    );
    await env.queue.send();
    expect(env.add.calls.where((c) => c.startsWith('create')), ['create k1 Pan -300000']);
    expect(env.capture.calls, ['save k2 Almuerzo:1500000,Uber:300000']);
    expect(env.server.items, hasLength(3));
    expect(env.state.notice!.sent, 3);
  });

  test('a save the server refuses is dropped and named; the rest still go up', () async {
    final env = _env();
    env.add.failures['create'] = const HomeFailure(422, code: 'category_not_found');
    await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
    await env.queue.add(PendingSave(key: 'k2', items: [_input('Leche', -500000)], batch: false));
    final notices = <PendingNotice>[];
    env.container.listen(pendingSavesProvider.select((s) => s.notice), (_, next) {
      if (next != null) notices.add(next);
    });
    await env.queue.send();
    expect(env.state.saves, isEmpty);
    expect(env.server.items.map((t) => t.name), ['Leche']);
    expect(notices.first.refused!.name, 'Pan');
    expect(notices.last.sent, 1);
  });

  test('a save refused because the vault is not open yet (423 vault_locked) waits, never dropped',
      () async {
    final env = _env();
    env.add.failures['create'] = const HomeFailure(423, code: 'vault_locked');
    await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
    await env.queue.send();
    expect(env.state.saves, hasLength(1));
    expect(env.state.notice?.refused, isNull);
    // The vault opened.
    await env.queue.send();
    expect(env.state.saves, isEmpty);
    expect(env.server.items.single.name, 'Pan');
  });

  test('canRetrySave: 423 vault_locked can work again, another 423 or a 4xx cannot', () {
    expect(canRetrySave(const HomeFailure(423, code: 'vault_locked')), isTrue);
    expect(canRetrySave(const HomeFailure(423, code: 'locked')), isFalse);
    expect(canRetrySave(const HomeFailure(422, code: 'category_not_found')), isFalse);
  });

  test('a refused save alone says which it was', () async {
    final env = _env();
    env.add.failures['create'] = const HomeFailure(422, code: 'category_not_found');
    await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
    await env.queue.send();
    expect(env.state.saves, isEmpty);
    expect(env.state.notice!.refused!.name, 'Pan');
  });

  test('a start finds what was waiting and sends it', () async {
    final store = FakePendingSavesStore()
      ..value = jsonEncode({
        'v': 1,
        'owner': sessionOwnerOf('t1'),
        'saves': [
          PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false).toJson(),
        ],
      });
    final env = _env(store: store);
    await _settle();
    await env.queue.send();
    expect(env.add.keys, ['k1']);
    expect(env.server.items.single.name, 'Pan');
    expect(env.state.saves, isEmpty);
  });

  test('another session reads nothing of what this one left', () async {
    final store = FakePendingSavesStore()
      ..value = jsonEncode({
        'v': 1,
        'owner': sessionOwnerOf('someone-else'),
        'saves': [
          PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false).toJson(),
        ],
      });
    final env = _env(store: store);
    await _settle();
    await env.queue.send();
    expect(env.add.keys, isEmpty);
    expect(env.state.saves, isEmpty);
  });

  group('a row not uploaded yet', () {
    test('an edit shows at once, and goes up after the save, with the save as it was', () async {
      final env = _env();
      env.add.failures['create'] = const HomeFailure(0);
      await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
      await env.queue.send();

      expect(
        await env.queue.edit('unsent-k1-0', const TransactionPatch(name: 'Pan integral')),
        isTrue,
      );
      final row = env.state.saves.single.rows('COP').single;
      expect(row.id, 'unsent-k1-0');
      expect(row.name, 'Pan integral');
      expect(row.amount, -300000);

      await env.queue.send();
      // The same key with the same body (a first try that did reach the server answers again),
      // then the edit on the server's row.
      expect(env.add.calls, [
        'create k1 Pan -300000',
        'create k1 Pan -300000',
        'update new-1 {name: Pan integral}',
      ]);
      expect(env.server.items.single.name, 'Pan integral');
      expect(env.state.saves, isEmpty);
      expect(env.state.notice!.sent, 1);
    });

    test('edits add up: the last value of each field wins', () async {
      final env = _env();
      env.add.failures['create'] = const HomeFailure(0);
      await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
      await env.queue.send();
      await env.queue.edit('unsent-k1-0', const TransactionPatch(name: 'Pan integral'));
      await env.queue.edit(
        'unsent-k1-0',
        const TransactionPatch(amount: -350000, pending: true, setNote: true, note: 'Panadería'),
      );
      final row = env.state.saves.single.rows('COP').single;
      expect(row.name, 'Pan integral');
      expect(row.amount, -350000);
      expect(row.status, TransactionStatusEnum.pending);
      expect(row.note, 'Panadería');

      await env.queue.send();
      final saved = env.server.items.single;
      expect(saved.name, 'Pan integral');
      expect(saved.amount, -350000);
      expect(saved.status, TransactionStatusEnum.pending);
      expect(saved.note, 'Panadería');
    });

    test('a delete hides it at once, and nothing is left once it goes up', () async {
      final env = _env();
      await env.queue.add(
        PendingSave(
          key: 'k1',
          items: [_input('Almuerzo', -1500000), _input('Uber', -300000)],
          batch: true,
        ),
      );
      env.capture.failures['save'] = const HomeFailure(0);
      await env.queue.send();

      expect(await env.queue.remove('unsent-k1-1'), isTrue);
      expect(env.state.saves.single.rows('COP').map((r) => r.name), ['Almuerzo']);

      await env.queue.send();
      expect(env.server.items.map((t) => t.name), ['Almuerzo']);
      expect(env.server.deleted.map((t) => t.name), ['Uber']);
      expect(env.state.saves, isEmpty);
      expect(env.state.notice!.sent, 1);
    });

    test('Deshacer before it goes up brings the row back, and nothing is deleted', () async {
      final env = _env();
      env.add.failures['create'] = const HomeFailure(0);
      await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
      await env.queue.send();
      await env.queue.remove('unsent-k1-0');
      expect(env.state.saves.single.rows('COP'), isEmpty);

      expect(await env.queue.restore('unsent-k1-0'), isTrue);
      expect(env.state.saves.single.rows('COP').single.name, 'Pan');
      await env.queue.send();
      expect(env.server.items.single.name, 'Pan');
      expect(env.server.calls.where((c) => c.startsWith('delete')), isEmpty);
    });

    test('edits and deletes are kept on the phone too', () async {
      final env = _env();
      await env.queue.add(
        PendingSave(
          key: 'k1',
          items: [_input('Almuerzo', -1500000), _input('Uber', -300000)],
          batch: true,
        ),
      );
      env.capture.failures['save'] = const HomeFailure(0);
      await env.queue.send();
      await env.queue.edit('unsent-k1-0', const TransactionPatch(name: 'Almuerzo ejecutivo'));
      await env.queue.remove('unsent-k1-1');
      await _settle();

      // The next start reads them back.
      final again = _env(store: FakePendingSavesStore()..value = env.store.value);
      // A start sends at once: still no network then.
      again.capture.failures['save'] = const HomeFailure(0);
      await _settle();
      expect(again.state.saves.single.rows('COP').map((r) => r.name), ['Almuerzo ejecutivo']);
      await again.queue.send();
      expect(again.server.items.map((t) => t.name), ['Almuerzo ejecutivo']);
      expect(again.server.deleted.map((t) => t.name), ['Uber']);
    });

    test('a save that went up but whose edit did not keeps the edit for the next try', () async {
      final env = _env();
      env.add.failures['create'] = const HomeFailure(0);
      await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
      await env.queue.send();
      await env.queue.edit('unsent-k1-0', const TransactionPatch(name: 'Pan integral'));
      env.add.failures['update'] = const HomeFailure(0);
      await env.queue.send();
      expect(env.server.items.single.name, 'Pan');
      expect(env.state.saves.single.rows('COP').single.name, 'Pan integral');

      await env.queue.send();
      // Not created twice: the server's id was kept.
      expect(env.add.calls.where((c) => c.startsWith('create')), hasLength(2));
      expect(env.server.items.single.name, 'Pan integral');
      expect(env.state.saves, isEmpty);
    });

    test('once it is up, the row is the server one: the queue says which one', () async {
      final env = _env();
      await env.queue.add(PendingSave(key: 'k1', items: [_input('Pan', -300000)], batch: false));
      await env.queue.send();
      expect(env.state.saves, isEmpty);
      expect(await env.queue.edit('unsent-k1-0', const TransactionPatch(name: 'X')), isFalse);
      expect(await env.queue.remove('unsent-k1-0'), isFalse);
      expect(env.queue.uploadedId('unsent-k1-0'), 'new-1');
    });
  });

  test('the rows stand for the movements, marked as not uploaded', () {
    const save = PendingSave(key: 'k1', items: [], batch: false);
    expect(
      isUnsent(
        Transaction(
          (b) => b
            ..id = save.rowId(0)
            ..name = ''
            ..amount = 0
            ..currency = 'COP'
            ..date = '2026-10-22'
            ..status = TransactionStatusEnum.paid
            ..categoryId = 'c'
            ..needsReview = false
            ..source_ = TransactionSource_Enum.app
            ..createdAt = ''
            ..updatedAt = '',
        ),
      ),
      isTrue,
    );
    final rows = PendingSave(key: 'k2', items: [_input('Pan', -300000)], batch: false).rows('COP');
    expect(rows.single.id, 'unsent-k2-0');
    expect(rows.single.amount, -300000);
    expect(rows.single.status, TransactionStatusEnum.paid);
  });
}
