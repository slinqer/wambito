// The widget's "hide the amount" choice lives in the widget's own preferences (where the widget's
// eye can write it), copied once from secure storage; unreadable means hidden.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/stored_flag.dart';
import 'package:wambito/feedback/vibration_setting.dart';
import 'package:wambito/home/widget_choice.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/home/widget_sync.dart';
import 'package:wambito/settings/preferences.dart';
import 'package:wambito/settings/settings_store.dart';

import '../settings/fakes.dart';
import 'fakes.dart';

class _BrokenFlagStore implements FlagStore {
  @override
  Future<bool?> read() async => throw StateError('keystore');

  @override
  Future<void> write(bool on) async => throw StateError('keystore');

  @override
  Future<void> clear() async => throw StateError('keystore');
}

void main() {
  test('the keys are persistent names', () {
    expect(widgetHideAmountKey, 'wambito.widget.hideAmount');
    expect(widgetVibrationKey, 'wambito.widget.vibration');
  });

  test('migrates a kept secure choice once', () async {
    final prefs = FakeWidgetStore();
    final legacy = FakeFlagStore(true);
    final store = WidgetPrefsFlagStore(prefs, legacy: legacy);
    expect(await store.read(), isTrue);
    expect(prefs.saved[widgetHideAmountKey], 'on');
    legacy.value = false;
    expect(await store.read(), isTrue, reason: 'the copy is done: the old key is ignored');
  });

  test('never chosen migrates as shown', () async {
    final prefs = FakeWidgetStore();
    final store = WidgetPrefsFlagStore(prefs, legacy: FakeFlagStore());
    expect(await store.read(), isNull);
    expect(prefs.saved[widgetHideAmountKey], 'off');
  });

  test('an unreadable legacy hides and retries at the next start', () async {
    final prefs = FakeWidgetStore();
    expect(await WidgetPrefsFlagStore(prefs, legacy: _BrokenFlagStore()).read(), isTrue);
    expect(prefs.saved.containsKey(widgetHideAmountKey), isFalse);
    expect(await WidgetPrefsFlagStore(prefs, legacy: FakeFlagStore(false)).read(), isFalse);
    expect(prefs.saved[widgetHideAmountKey], 'off');
  });

  test('writes and clears its own key', () async {
    final prefs = FakeWidgetStore();
    final store = WidgetPrefsFlagStore(prefs, legacy: FakeFlagStore());
    await store.write(true);
    expect(prefs.saved[widgetHideAmountKey], 'on');
    await store.clear();
    expect(prefs.saved.containsKey(widgetHideAmountKey), isFalse);
  });

  test('a tap on the widget is read back by the app (reload)', () async {
    final prefs = FakeWidgetStore();
    final c = ProviderContainer(
      overrides: [
        widgetStoreProvider.overrideWithValue(prefs),
        flagStoreProvider.overrideWith((ref, key) => FakeFlagStore()),
      ],
    );
    addTearDown(c.dispose);
    await c.read(hideWidgetAmountProvider.notifier).ready;
    expect(c.read(hideWidgetAmountProvider), isFalse);
    prefs.saved[widgetHideAmountKey] = 'on'; // the widget's eye, while the app was away
    await c.read(hideWidgetAmountProvider.notifier).reload();
    expect(c.read(hideWidgetAmountProvider), isTrue);
  });

  test('the vibration switch is mirrored where the widget reads it', () async {
    final prefs = FakeWidgetStore();
    final c = ProviderContainer(
      overrides: [
        widgetStoreProvider.overrideWithValue(prefs),
        flagStoreProvider.overrideWith(
          (ref, key) => FakeFlagStore(key == vibrationSettingKey ? false : null),
        ),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      ],
    );
    addTearDown(c.dispose);
    c.read(widgetSyncProvider);
    await c.read(vibrationEnabledProvider.notifier).ready;
    await Future<void>.delayed(Duration.zero);
    expect(prefs.saved[widgetVibrationKey], 'off');
    await c.read(vibrationEnabledProvider.notifier).set(true);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.saved[widgetVibrationKey], 'on');
  });
}
