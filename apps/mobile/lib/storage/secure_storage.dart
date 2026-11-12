import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The secure storage every store in the app uses. On iOS an item is readable after the first
/// unlock of the phone (not only while it is unlocked), so a background job can read the session
/// while the phone is locked; it never leaves this phone. Android keeps the plugin's defaults:
/// native code reads the same storage with fixed options, and changing them would cost people
/// their session.
const FlutterSecureStorage appSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

/// Marks that the items below were rewritten with the accessibility it names.
const accessibilityFlagKey = 'wambito.storage.accessibility';
const _accessibility = 'first_unlock_this_device';

/// The items a background job reads while the phone is locked.
const backgroundReadableKeys = ['session.token', 'session.guest', 'setting.server'];

/// On iOS, rewrites [keys] with [storage]'s options, once: an item stored before
/// [appSecureStorage] existed keeps its old accessibility until it is written again. Nothing is
/// ever deleted here; a key that cannot be read is left as it is and the flag is not set, so the
/// next start tries again.
Future<void> migrateKeychainAccessibility(FlutterSecureStorage storage, List<String> keys) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    if (await storage.read(key: accessibilityFlagKey) == _accessibility) return;
    var complete = true;
    for (final key in keys) {
      try {
        final value = await storage.read(key: key);
        if (value != null) await storage.write(key: key, value: value);
      } on PlatformException {
        complete = false;
      }
    }
    if (complete) await storage.write(key: accessibilityFlagKey, value: _accessibility);
  } on PlatformException {
    // The Keychain is not readable now (the phone is locked after a restart): try at the next start.
  }
}
