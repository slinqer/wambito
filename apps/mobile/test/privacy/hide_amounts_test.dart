// The app eye's choice: kept in the settings store, read at start (so a closed eye hides the
// first frame), one per phone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/server_address.dart';
import 'package:wambito/privacy/hide_amounts.dart';
import 'package:wambito/settings/initial_settings.dart';
import 'package:wambito/settings/settings_store.dart';

import '../settings/fakes.dart';

ProviderContainer _container(SettingsStore store, {InitialSettings? initial}) {
  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWithValue(store),
      if (initial != null) initialSettingsProvider.overrideWithValue(initial),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _BrokenStore implements SettingsStore {
  @override
  Future<String?> read(String key) async => throw StateError('keystore');

  @override
  Future<void> write(String key, String value) async => throw StateError('keystore');

  @override
  Future<void> delete(String key) async => throw StateError('keystore');
}

void main() {
  test('the key is a persistent name', () {
    expect(hideAmountsKey, 'setting.app.hideAmounts');
  });

  test('reads on as hidden at start, anything else as shown', () async {
    expect(
      (await InitialSettings.read(FakeSettingsStore({hideAmountsKey: 'on'}))).hideAmounts,
      isTrue,
    );
    expect(
      (await InitialSettings.read(FakeSettingsStore({hideAmountsKey: 'off'}))).hideAmounts,
      isFalse,
    );
    expect(
      (await InitialSettings.read(FakeSettingsStore({hideAmountsKey: 'x'}))).hideAmounts,
      isFalse,
    );
    expect((await InitialSettings.read(FakeSettingsStore())).hideAmounts, isFalse);
    expect(InitialSettings.defaults.hideAmounts, isFalse);
  });

  test('starts from the initial settings, so the first frame is already hidden', () {
    final container = _container(
      FakeSettingsStore(),
      initial: InitialSettings(
        serverUrl: defaultServerUrl,
        themeMode: ThemeMode.dark,
        hideAmounts: true,
      ),
    );
    expect(container.read(amountsHiddenProvider), isTrue);
  });

  test('set keeps the choice in the settings store and the next start reads it', () async {
    final store = FakeSettingsStore();
    final container = _container(store);
    expect(container.read(amountsHiddenProvider), isFalse);
    await container.read(amountsHiddenProvider.notifier).set(true);
    expect(container.read(amountsHiddenProvider), isTrue);
    expect(store.values[hideAmountsKey], 'on');
    expect((await InitialSettings.read(store)).hideAmounts, isTrue);
    await container.read(amountsHiddenProvider.notifier).set(false);
    expect(store.values[hideAmountsKey], 'off');
  });

  test('a store that fails to write keeps the choice for this run', () async {
    final container = _container(_BrokenStore());
    await container.read(amountsHiddenProvider.notifier).set(true);
    expect(container.read(amountsHiddenProvider), isTrue);
  });
}
