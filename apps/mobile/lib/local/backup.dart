import 'package:flutter/services.dart';

const _channel = MethodChannel('wambito/device');

/// Keeps [path] (the vault's folder) out of iCloud and device backups. On iOS it sets the
/// "excluded from backup" flag; Android excludes by XML (`res/xml/backup_rules.xml`,
/// `data_extraction_rules.xml`), so its side only answers true. A host without the method (a
/// test, a desktop) is not an error.
Future<void> excludeVaultFromBackup(String path) async {
  try {
    await _channel.invokeMethod<bool>('excludeFromBackup', {'path': path});
  } on MissingPluginException {
    // no native side here
  }
}
