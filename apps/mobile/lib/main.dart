import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'api/device.dart';
import 'app.dart';
import 'background/background_main.dart';
import 'local/install_marker.dart';
import 'local/key_storage.dart';
import 'vault/encryption_mode.dart' show EncryptionStore;
import 'settings/initial_settings.dart';
import 'settings/licenses.dart';
import 'settings/settings_store.dart';

Future<void> main() async {
  runApp(await bootstrap());
}

/// The headless entry points native code starts in a background engine (D22): a periodic or
/// one-off sync, and a run that saves the queued notification captures first.
@pragma('vm:entry-point')
Future<void> syncMain() => backgroundMain('sync');

@pragma('vm:entry-point')
Future<void> captureMain() => backgroundMain('capture');

/// The app with the phone's time zone and language read first (every request sends them), and the
/// server, theme and language the person chose in Settings.
/// [overrides] are for the integration tests (a fixed transcript in place of audio, say).
Future<Widget> bootstrap({List<Override> overrides = const []}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything reads secure storage: the Keychain keeps items across a reinstall, the vault
  // file does not, so keys left by an earlier install go now.
  try {
    await clearKeysAfterReinstall(
      KeyStorage(),
      FileInstallMarker(),
      markSession: const EncryptionStore().markReinstalled,
    );
  } on Object {
    // Secure storage or the support folder is not readable now: the marker stays unwritten and the
    // next start tries again.
  }
  registerExtraLicenses();
  final hints = await DeviceHints.read();
  final settings = await InitialSettings.read(const SecureSettingsStore());
  return ProviderScope(
    overrides: [
      deviceHintsProvider.overrideWithValue(hints),
      initialSettingsProvider.overrideWithValue(settings),
      ...overrides,
    ],
    child: const WambitoApp(),
  );
}
