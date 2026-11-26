import '../feedback/stored_flag.dart';
import 'widget_snapshot.dart';

/// The widget's own "hide the amount" choice (`on` / `off`), in the widget's preferences
/// (`HomeWidgetPreferences`), where both the app's Settings switch and the widget's eye
/// (`ToggleHideAmount.kt`) write it. A persistent name.
const widgetHideAmountKey = 'wambito.widget.hideAmount';

/// The app's vibration switch (`on` / `off`), mirrored for the widget's eye, which plays the blinds
/// without the app. A persistent name.
const widgetVibrationKey = 'wambito.widget.vibration';

/// The widget's hide choice kept under [widgetHideAmountKey]. Until that key exists, the choice
/// kept in secure storage before ([legacy]) is copied over once: never chosen is written `off`;
/// an unreadable one reads as hidden (never shown by guess) and is tried again at the next start.
class WidgetPrefsFlagStore implements FlagStore {
  const WidgetPrefsFlagStore(this._store, {required this.legacy});

  final WidgetStore _store;

  /// Where the choice was kept before.
  final FlagStore legacy;

  @override
  Future<bool?> read() async {
    switch (await _store.read(widgetHideAmountKey)) {
      case 'on':
        return true;
      case 'off':
        return false;
    }
    final bool? kept;
    try {
      kept = await legacy.read();
    } on Object {
      return true;
    }
    await write(kept ?? false);
    return kept;
  }

  @override
  Future<void> write(bool on) => _store.save(widgetHideAmountKey, on ? 'on' : 'off');

  @override
  Future<void> clear() => _store.remove(widgetHideAmountKey);
}
