// The `widget` effect of a background run: the widget drawn from the vault, owner-checked.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/background/widget_effect.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/local/backend.dart';

import '../home/fakes.dart';
import '../home/vault_backend.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 18);
  late FakeWidgetStore store;

  setUp(() => store = FakeWidgetStore());

  Future<void> Function(String, LocalBackend) effect({
    Future<bool> Function()? hide,
    Future<bool> Function(String)? owns,
  }) => widgetEffect(
    store: store,
    hideAmount: hide ?? () async => false,
    theme: 'light',
    locale: 'en',
    now: () => now,
    owns: owns ?? (id) async => true,
  );

  test('draws the vault with its owner, the theme and the language of the settings', () async {
    await effect()('u1', await seededVaultBackend(now));
    final doc = jsonDecode(store.saved[widgetSnapshotKey]!) as Map<String, Object?>;
    expect(doc['owner'], 'u1');
    expect(doc['spent'], 5000000);
    expect(doc['theme'], 'light');
    expect(doc['locale'], 'en');
    expect(doc['hideAmount'], isFalse);
  });

  test('carries the hide-amount choice', () async {
    await effect(hide: () async => true)('u1', await seededVaultBackend(now));
    final doc = jsonDecode(store.saved[widgetSnapshotKey]!) as Map<String, Object?>;
    expect(doc['hideAmount'], isTrue);
  });

  test('writes nothing when the account is no longer the signed-in one', () async {
    await effect(owns: (id) async => false)('u1', await seededVaultBackend(now));
    expect(store.saved, isEmpty);
  });
}
