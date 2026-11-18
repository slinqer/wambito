import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the API learns about the phone with every request: its IANA time zone
/// (`x-wambito-timezone`) and its language tag (`x-wambito-locale`). A new user's profile, currency
/// included, starts from them, guest or email (apps/api/src/auth.ts, `guestDefaults`).
class DeviceHints {
  const DeviceHints({required this.timezone, required this.locale, this.appVersion});

  /// Until the phone has answered, and in tests: the API then falls back to UTC and Spanish.
  static const fallback = DeviceHints(timezone: 'UTC', locale: 'es');

  static const _channel = MethodChannel('wambito/device');

  /// The phone's settings: the zone from Android (Dart only knows its abbreviation), the
  /// language as a BCP 47 tag such as `es-CO`, which also carries the region.
  static Future<DeviceHints> read() async {
    String? zone;
    try {
      zone = await _channel.invokeMethod<String>('timeZone');
    } on PlatformException {
      zone = null;
    } on MissingPluginException {
      zone = null;
    }
    String? version;
    try {
      version = await _channel.invokeMethod<String>('appVersion');
    } on PlatformException {
      version = null;
    } on MissingPluginException {
      version = null;
    }
    return DeviceHints(
      timezone: (zone == null || zone.isEmpty) ? fallback.timezone : zone,
      locale: PlatformDispatcher.instance.locale.toLanguageTag(),
      appVersion: version,
    );
  }

  final String timezone;
  final String locale;

  /// The build's version (`x-wambito-version`), when the phone said it.
  final String? appVersion;

  static final _versionShape = RegExp(r'^[A-Za-z0-9.+_-]{1,64}$');

  /// The request headers, as the API names them. `x-wambito-client` is `ios` on an iPhone and
  /// `android` elsewhere; either marks the magic link of a sign-in started here `from=app`, so the
  /// web page it opens offers to open this app, and names the user's platform
  /// (apps/api/src/auth.ts, `platformOf`).
  Map<String, String> get headers => {
    'x-wambito-timezone': timezone,
    'x-wambito-locale': locale,
    'x-wambito-client': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    if (appVersion != null && _versionShape.hasMatch(appVersion!)) 'x-wambito-version': appVersion!,
  };
}

/// The phone's [DeviceHints], read once at start (main.dart overrides this).
final deviceHintsProvider = Provider<DeviceHints>((ref) => DeviceHints.fallback);
