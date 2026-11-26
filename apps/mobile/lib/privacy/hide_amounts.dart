import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/initial_settings.dart';
import '../settings/settings_store.dart';

export '../settings/settings_store.dart' show hideAmountsKey;

/// Home's eye: true hides every amount the app draws (a demo, the phone handed over). One choice
/// per phone, kept until the eye is tapped again; it starts from [InitialSettings], read before the
/// first frame, so a closed eye never shows an amount for a moment. The widget has its own choice.
class HideAmounts extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialSettingsProvider).hideAmounts;

  Future<void> set(bool hidden) async {
    state = hidden;
    try {
      await ref.read(settingsStoreProvider).write(hideAmountsKey, hidden ? 'on' : 'off');
    } on Object {
      // Not kept: the choice holds for this run.
    }
  }
}

final amountsHiddenProvider = NotifierProvider<HideAmounts, bool>(HideAmounts.new);
