import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/initial_settings.dart';
import '../storage/secure_storage.dart';
import '../settings/settings_store.dart';
import 'server_address.dart';
import 'session.dart';

export 'server_address.dart';

/// The server the app talks to (spec section 6.1): the Wambito one until the person changes it in
/// Settings. Everything that calls the API watches this, so a change points every call at the new
/// server at once.
class ServerUrl extends Notifier<Uri> {
  @override
  Uri build() => ref.watch(initialSettingsProvider).serverUrl;

  /// Points the app at [raw]. Another server is another set of accounts, so the session is ended
  /// first (and the old server told, as well as it can): the caller has already warned a guest.
  /// Returns false, changing nothing, when [raw] is not an address the app may talk to.
  Future<bool> change(String raw) async {
    final next = parseServerUrl(raw);
    if (next == null) return false;
    if (next == state) return true;
    await ref.read(sessionProvider.notifier).signOut(discardGuest: true);
    try {
      await ref.read(settingsStoreProvider).write(serverUrlKey, next.toString());
    } on Object {
      // Not kept: the next start goes back to the old server.
    }
    state = next;
    return true;
  }
}

final serverUrlProvider = NotifierProvider<ServerUrl, Uri>(ServerUrl.new);

/// [newUsersEncryptedByBuild], replaced in tests.
final newUsersEncryptedByBuildProvider = Provider<bool>((ref) => newUsersEncryptedByBuild);

/// Secure storage key of what this phone saw [server] make of a new anonymous user: `encrypted`
/// once one was `preview` ([rememberNewUsersEncrypted]). A persistent name.
String newUsersKeyOf(Uri server) => 'wambito.server.${server.host}.newUsers';

/// Whether new users of the current server are known to be encrypted (ruling 8): the build says so
/// ([newUsersEncryptedByBuildProvider]), or this phone already saw that server make a `preview`
/// anonymous user ([newUsersKeyOf] is `encrypted`). Follows [serverUrlProvider]. Only then may an
/// offline "Start" open a provisional vault; else it needs the network. Unreadable: false.
final newUsersEncryptedProvider = FutureProvider<bool>((ref) async {
  final server = ref.watch(serverUrlProvider);
  if (ref.watch(newUsersEncryptedByBuildProvider)) return true;
  try {
    return await appSecureStorage.read(key: newUsersKeyOf(server)) == 'encrypted';
  } on Object {
    return false;
  }
});

/// [server] made a `preview` anonymous user: from now on an offline "Start" on it may open a
/// provisional vault. Best effort.
Future<void> rememberNewUsersEncrypted(Uri server) async {
  try {
    await appSecureStorage.write(key: newUsersKeyOf(server), value: 'encrypted');
  } on Object {
    // The next encrypted user is remembered instead.
  }
}

/// [server] made a `plain` user after all (a provisional promotion found one): what was kept goes,
/// so the next offline "Start" asks for the network again. Best effort.
Future<void> forgetNewUsersEncrypted(Uri server) async {
  try {
    await appSecureStorage.delete(key: newUsersKeyOf(server));
  } on Object {
    // Kept: the next promotion finds the plain user again and says so.
  }
}
