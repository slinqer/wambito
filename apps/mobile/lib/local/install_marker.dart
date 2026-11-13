import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'key_storage.dart';

/// Whether this install of the app has run before. App files go with the app when it is
/// uninstalled, on both platforms; Keychain items do not (iOS keeps them across a reinstall). So a
/// missing marker with keys in secure storage means keys left over from an earlier install, whose
/// vault file is gone: they are deleted before anything reads them.
abstract interface class InstallMarker {
  Future<bool> exists();
  Future<void> write();
}

/// The marker as a file, `wambito.installed`, in Application Support.
class FileInstallMarker implements InstallMarker {
  /// [directory] is for tests; the app leaves it out.
  FileInstallMarker([this._directory]);

  final String? _directory;

  static const fileName = 'wambito.installed';

  Future<File> _file() async =>
      File(p.join(_directory ?? (await getApplicationSupportDirectory()).path, fileName));

  @override
  Future<bool> exists() async => (await _file()).exists();

  @override
  Future<void> write() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString('1', flush: true);
  }
}

/// On the first start of an install (no marker): deletes every `wambito.vault.*`,
/// `wambito.encryption.*` and `wambito.account` item of secure storage (the kept account is
/// personal data, which must not survive an iOS reinstall), then writes the marker. Call it before
/// anything reads secure storage. A failure leaves the marker unwritten, so the next start tries again.
Future<void> clearKeysAfterReinstall(KeyStorage storage, InstallMarker marker) async {
  if (await marker.exists()) return;
  await storage.deleteAllVaultKeys();
  await marker.write();
}
