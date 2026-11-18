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

/// What is kept under [newUsersKeyOf] once [server] made a `plain` user (a provisional promotion
/// found one): `plain <build> <day>`, so an offline "Start" asks for the network again, and the
/// promotion probes that server (making an anonymous user each time) at most once a day per build.
String _plainMark(String build, String day) => 'plain $build $day';

/// [server] made a `plain` user on [day] (`yyyy-mm-dd`, local) for [build]. Best effort.
Future<void> rememberNewUsersPlain(Uri server, {required String build, required String day}) async {
  try {
    await appSecureStorage.write(key: newUsersKeyOf(server), value: _plainMark(build, day));
  } on Object {
    // The next promotion probes again.
  }
}

/// Whether [server] was already found making `plain` users by this [build] on [day]: then the
/// promotion does not probe it again (it would only make another empty user). Unreadable: false.
Future<bool> newUsersPlainProbed(Uri server, {required String build, required String day}) async {
  try {
    return await appSecureStorage.read(key: newUsersKeyOf(server)) == _plainMark(build, day);
  } on Object {
    return false;
  }
}
