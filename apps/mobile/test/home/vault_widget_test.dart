// The widget of a `preview` account, drawn from the vault on the phone by Dart.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/home/vault_widget.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/local/backend.dart';
import 'package:wambito/local/memory_store.dart';

import 'fakes.dart';
import 'vault_backend.dart';

final _now = DateTime.utc(2026, 10, 21, 18);

void main() {
  late FakeWidgetStore store;

  setUp(() => store = FakeWidgetStore());

  Future<bool> write(
    LocalBackend backend, {
    Future<bool> Function()? stillOwner,
    bool hideAmount = false,
  }) => writeVaultWidget(
    userId: 'u1',
    backend: backend,
    store: store,
    hideAmount: hideAmount,
    theme: 'dark',
    locale: 'es',
    now: _now,
    stillOwner: stillOwner ?? () async => true,
  );

  test("writes the vault's figures with the owner", () async {
    expect(await write(await seededVaultBackend(_now)), isTrue);
    final doc = jsonDecode(store.saved[widgetSnapshotKey]!) as Map<String, Object?>;
    expect(doc, {
      'v': 3,
      'signedIn': true,
      'remaining': -5000000,
      'spent': 5000000,
      'budgetTotal': 0,
      'currency': 'COP',
      'locale': 'es',
      'month': '2026-10',
      'mood': 'happy',
      'updatedAt': '2026-10-21T18:00:00.000Z',
      'hideAmount': false,
      'theme': 'dark',
      'timezone': 'America/Bogota',
      'owner': 'u1',
    });
    expect(store.updates, 1);
  });

  test('writes nothing when the owner changed meanwhile', () async {
    expect(await write(await seededVaultBackend(_now), stillOwner: () async => false), isFalse);
    expect(store.saved, isEmpty);
    expect(store.updates, 0);
  });

  test('the hidden amount is carried into the snapshot', () async {
    await write(await seededVaultBackend(_now), hideAmount: true);
    final doc = jsonDecode(store.saved[widgetSnapshotKey]!) as Map<String, Object?>;
    expect(doc['hideAmount'], isTrue);
  });

  test('an answer that is not a summary writes nothing', () async {
    final empty = createLocalBackend(
      store: createMemoryStore(),
      now: () => _now,
      unavailable: const [],
    );
    final refused = _Refusing(empty);
    expect(await write(refused), isFalse);
    expect(store.saved, isEmpty);
  });
}

class _Refusing implements LocalBackend {
  _Refusing(this._inner);

  final LocalBackend _inner;

  @override
  Future<LocalResponse?> handle(
    String method,
    String path,
    Map<String, Object> query,
    Object? body, {
    Map<String, String> headers = const {},
  }) async => path == '/v1/summary'
      ? const LocalResponse(500, null)
      : _inner.handle(method, path, query, body);
}
