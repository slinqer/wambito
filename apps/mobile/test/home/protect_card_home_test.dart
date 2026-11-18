// Home's "Protect your data" card (phone-first spec 5.2) in front of a vault: it shows while neither
// step is done and goes once one is; it keeps off the add button; "Not now" is kept across a restart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/protect/protect_card.dart';
import 'package:wambito/protect/protect_status.dart';
import 'package:wambito/vault/vault_providers.dart' show vaultSessionProvider;

import '../protect/fakes.dart';
import 'fakes.dart';
import 'fixtures.dart';
import 'home_harness.dart';

class _MemoryCardStore implements ProtectCardStore {
  final states = <String, ProtectCardState>{};

  @override
  Future<ProtectCardState?> read(String userId) async => states[userId];

  @override
  Future<void> write(String userId, ProtectCardState state) async => states[userId] = state;
}

ProtectStatus _status({bool recoveryKey = false, bool passkey = false}) => ProtectStatus(
  recoveryKey: recoveryKey,
  passkey: passkey,
  passkeyOffered: true,
  passkeyWithoutPrf: false,
);

void main() {
  const card = Key('home.protectCard');

  FakeHomeRepository withMovement() =>
      FakeHomeRepository(items: [tx('t1', '2026-10-20', -500000, name: 'Pan')]);

  /// A vault whose account was first seen [days] ago (the card's store says so).
  Future<(FakeVault, _MemoryCardStore)> vaultSeen(WidgetTester t, {required int days}) async {
    final vault = FakeVault();
    await t.runAsync(() => vault.seeded);
    final store = _MemoryCardStore()
      ..states['user-1'] = ProtectCardState(firstOpen: testNow.subtract(Duration(days: days)));
    return (vault, store);
  }

  testWidgets('the card shows while neither step is done and goes once one is', (t) async {
    final (vault, cards) = await vaultSeen(t, days: 8);
    var recoveryDone = false;
    final h = await pumpHome(
      t,
      withMovement(),
      overrides: [
        vaultSessionProvider.overrideWithValue(vault),
        protectCardStoreProvider.overrideWithValue(cards),
        protectStatusProvider.overrideWith((ref) async => _status(recoveryKey: recoveryDone)),
      ],
    );
    expect(find.byKey(card), findsOneWidget);
    expect(find.byKey(const Key('protect.cardGo')), findsOneWidget);

    recoveryDone = true;
    h.container.invalidate(protectStatusProvider);
    await t.pumpAndSettle();
    expect(find.byKey(card), findsNothing);
  });

  testWidgets('the card is not due in the first days with few movements', (t) async {
    final (vault, cards) = await vaultSeen(t, days: 2);
    await pumpHome(
      t,
      withMovement(),
      overrides: [
        vaultSessionProvider.overrideWithValue(vault),
        protectCardStoreProvider.overrideWithValue(cards),
        protectStatusProvider.overrideWith((ref) async => _status()),
      ],
    );
    expect(find.byKey(card), findsNothing);
  });

  testWidgets('the first evaluation writes firstOpen; 20 movements make it due at once', (t) async {
    final vault = FakeVault();
    await t.runAsync(() async {
      await vault.seeded;
      for (var i = 0; i < 20; i++) {
        await vault.store.put(
          RecordType.transaction,
          '01930000-0000-7000-8000-${'$i'.padLeft(12, '0')}',
          {'n': i},
        );
      }
    });
    final cards = _MemoryCardStore();
    await pumpHome(
      t,
      withMovement(),
      overrides: [
        vaultSessionProvider.overrideWithValue(vault),
        protectCardStoreProvider.overrideWithValue(cards),
        protectStatusProvider.overrideWith((ref) async => _status()),
      ],
    );
    // The memory store's queue was built in the real zone: let it turn once.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(cards.states['user-1']!.firstOpen, testNow);
    expect(find.byKey(card), findsOneWidget);
  });

  testWidgets('it never covers the add button', (t) async {
    final (vault, cards) = await vaultSeen(t, days: 8);
    await pumpHome(
      t,
      withMovement(),
      overrides: [
        vaultSessionProvider.overrideWithValue(vault),
        protectCardStoreProvider.overrideWithValue(cards),
        protectStatusProvider.overrideWith((ref) async => _status()),
      ],
    );
    expect(find.byKey(card), findsOneWidget);
    final add = find.byKey(const Key('home.add'));
    expect(add, findsOneWidget);
    expect(t.getRect(add).overlaps(t.getRect(find.byKey(card))), isFalse);
    // the add sheet still opens
    await t.tap(add);
    await t.pumpAndSettle();
    expect(find.byKey(card).hitTestable(), findsNothing);
  });

  testWidgets('Not now keeps the dismissal across a restart', (t) async {
    final (vault, cards) = await vaultSeen(t, days: 8);
    final overrides = [
      vaultSessionProvider.overrideWithValue(vault),
      protectCardStoreProvider.overrideWithValue(cards),
      protectStatusProvider.overrideWith((ref) async => _status()),
    ];
    await pumpHome(t, withMovement(), overrides: overrides);
    await t.tap(find.byKey(const Key('protect.cardLater')));
    await t.pumpAndSettle();
    expect(find.byKey(card), findsNothing);
    expect(cards.states['user-1']!.dismissals, 1);

    // The next start: the same phone, a new home.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 15));
    await pumpHome(t, withMovement(), overrides: overrides);
    expect(find.byKey(card), findsNothing);
  });

  testWidgets('a plain account sees today\'s home: no card', (t) async {
    await pumpHome(t, withMovement());
    expect(find.byKey(card), findsNothing);
  });
}
