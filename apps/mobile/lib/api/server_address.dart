import 'package:flutter/foundation.dart' show kDebugMode;

/// The server the app talks to unless the person changes it (spec section 6.1): a build can point
/// at another one with `--dart-define=WAMBITO_SERVER=http://10.0.2.2:3000` (the dev stack, seen
/// from the emulator).
final defaultServerUrl = Uri.parse(
  const String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'https://app.wambito.com'),
);

/// Whether the server this build talks to makes every new user encrypted (`preview`): builds made
/// from the switch day on say so with `--dart-define=WAMBITO_NEW_USERS_ENCRYPTED=true` (default
/// false). Only then, or once this phone saw the server make an encrypted user
/// (`newUsersEncryptedProvider`, lib/api/server_url.dart), does "Start" work without the network,
/// on a provisional vault (ruling 8): a `plain` user never gets a movement made offline.
const bool newUsersEncryptedByBuild = bool.fromEnvironment('WAMBITO_NEW_USERS_ENCRYPTED');

/// The hosts that may use plain `http`, in debug builds only: the phone's own `localhost` and the
/// emulator's name for the computer it runs on. A release build refuses plain `http` outright (it
/// has no cleartext permission anyway), so a typo there says so at once.
const _developmentHosts = {'localhost', '10.0.2.2'};

/// [raw] as a server address, or null when the app must not talk to it: an `https` address, or (when
/// [development], which is true in debug builds only) an `http` one for [_developmentHosts]; no
/// user info, query or fragment. A trailing slash is dropped, so one server has one spelling.
Uri? parseServerUrl(String raw, {bool development = kDebugMode}) {
  final text = raw.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
  final Uri parsed;
  try {
    parsed = Uri.parse(text);
  } on FormatException {
    return null;
  }
  if (!parsed.hasAuthority || parsed.host.isEmpty) return null;
  if (parsed.userInfo.isNotEmpty || parsed.hasQuery || parsed.hasFragment) return null;
  final secure = parsed.scheme == 'https';
  final plainHttp =
      development && parsed.scheme == 'http' && _developmentHosts.contains(parsed.host);
  if (!secure && !plainHttp) return null;
  if (parsed.hasPort && (parsed.port < 1 || parsed.port > 65535)) return null;
  final path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
  try {
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: path.isEmpty ? null : path,
    );
  } on FormatException {
    return null;
  }
}
