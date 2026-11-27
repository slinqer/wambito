import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/theme/tokens.g.dart';

// Checks that the Kotlin side of the home-screen widget (android/.../widget/) agrees with the Dart
// side it cannot import: the colours, the secure storage options, the snapshot version, the
// receivers' names, and the manifest entries.

const _widget = 'android/app/src/main/kotlin/com/wambito/app/widget';
final _manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

String _kotlin(String file) => File('$_widget/$file').readAsStringSync();

int _argb(Color color) => color.toARGB32();

/// RRGGBB in capitals, as the vector drawables write it.
String _hex(Color color) =>
    (_argb(color) & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

void main() {
  test("the widget's colours are the app's tokens, night and day", () {
    final source = _kotlin('WidgetContent.kt');
    final entries = RegExp(r'"(\w+)" to \(0x([0-9A-Fa-f]{8}) to 0x([0-9A-Fa-f]{8})\)')
        .allMatches(source)
        .toList();
    expect(entries, isNotEmpty);
    const night = WambitoColors.night;
    const day = WambitoColors.day;
    final tokens = <String, (Color, Color)>{
      'surface': (night.surface, day.surface),
      'ink': (night.ink, day.ink),
      'inkMuted': (night.inkMuted, day.inkMuted),
      'brand': (night.brand, day.brand),
      'brandEdge': (night.brandEdge, day.brandEdge),
      'onBrand': (night.onBrand, day.onBrand),
      'stroke': (night.stroke, day.stroke),
      'good': (night.good, day.good),
      'near': (night.near, day.near),
      'over': (night.over, day.over),
    };
    for (final entry in entries) {
      final name = entry.group(1)!;
      expect(tokens.containsKey(name), isTrue, reason: '$name is not a token here');
      final (n, d) = tokens[name]!;
      expect(int.parse(entry.group(2)!, radix: 16), _argb(n), reason: '$name at night');
      expect(int.parse(entry.group(3)!, radix: 16), _argb(d), reason: '$name by day');
    }
    expect(entries.map((e) => e.group(1)).toSet(), tokens.keys.toSet());
  });

  Map<String, String> pairs(String block) => {
    for (final m in RegExp(r'"(\w+)" to "([^"]*)"').allMatches(block)) m.group(1)!: m.group(2)!,
  };

  test('the refresh job reads secure storage where and how Dart writes it', () {
    final source = _kotlin('SecureSession.kt');
    final start = source.indexOf('val DART_DEFAULT_OPTIONS');
    final workerStart = source.indexOf('val WORKER_OPTIONS');
    expect(pairs(source.substring(start, workerStart)), AndroidOptions.defaultOptions.toMap());
  });

  test('but the refresh job never lets the plugin delete or migrate anything', () {
    final source = _kotlin('SecureSession.kt');
    final worker = pairs(source.substring(source.indexOf('val WORKER_OPTIONS')));
    expect(worker, {'resetOnError': 'false', 'migrateOnAlgorithmChange': 'false'});
  });

  test('the refresh job reads the keys the app writes', () {
    final source = _kotlin('SecureSession.kt');
    expect(source, contains('TOKEN_KEY = "session.token"'));
    expect(source, contains('SERVER_KEY = "setting.server"'));
  });

  test('both sides agree on the snapshot: key, version, receivers', () {
    final snapshot = _kotlin('WidgetSnapshot.kt');
    expect(snapshot, contains('KEY = "$widgetSnapshotKey"'));
    expect(snapshot, contains('VERSION = $widgetSnapshotVersion'));
    for (final receiver in widgetReceivers) {
      final name = receiver.split('.').last;
      expect(_manifest, contains('android:name=".widget.$name"'));
      expect(
        File('$_widget/${name.replaceFirst('Receiver', '')}.kt').readAsStringSync(),
        contains('class $name'),
      );
    }
  });

  test('both sides agree on the owner of a snapshot', () {
    final snapshot = _kotlin('WidgetSnapshot.kt');
    expect(snapshot, contains('doc.put("owner", owner)'));
    expect(snapshot, contains('doc.optString("owner", "")'));
    final account = File('android/app/src/main/kotlin/com/wambito/app/account/AccountMode.kt')
        .readAsStringSync();
    expect(account, contains('OWNER_KEY = "wambito.encryption.owner"'));
    // Dart writes it under the same name as the field Kotlin reads.
    final dart = File('lib/home/widget_snapshot.dart').readAsStringSync();
    expect(dart, contains("'owner': ?owner"));
  });

  test('the deep links: wambito://, only through a not-exported alias', () {
    final alias = RegExp(
      r'<activity-alias((?:(?!</activity-alias>).)*)</activity-alias>',
      dotAll: true,
    ).firstMatch(_manifest)!.group(1)!;
    expect(alias, contains('android:name=".LaunchLinkAlias"'));
    expect(alias, contains('android:exported="false"'));
    expect(alias, contains('android:targetActivity=".MainActivity"'));
    for (final host in ['add', 'capture', 'due', 'progress', 'home']) {
      expect(alias, contains('android:scheme="wambito" android:host="$host"'));
    }
    final aliasSchemes = RegExp(r'android:scheme="([^"]+)"').allMatches(alias).map((m) => m[1]);
    expect(aliasSchemes.toSet(), {'wambito'});
    expect(alias, isNot(contains('BROWSABLE')));
    // The exported launcher activity takes no wambito:// link, since other apps can start it, but
    // the web sign-in's QR (phone-first ruling 14): the system camera opens it, and it only opens
    // the approval, where the person still has to approve.
    final main = RegExp(
      r'<activity\s((?:(?!</activity>).)*)</activity>',
      dotAll: true,
    ).firstMatch(_manifest)!.group(1)!;
    expect(main, contains('android:name=".MainActivity"'));
    final wambito = RegExp(r'<data android:scheme="wambito"[^>]*>')
        .allMatches(main)
        .map((m) => m[0]);
    expect(wambito, ['<data android:scheme="wambito" android:host="signin"/>']);
  });

  test('the app is Wambito on the phone', () {
    // The label is a placeholder: Wambito, or "Wambito Dev" for the opt-in side-by-side build.
    expect(_manifest, contains('android:label="\${appLabel}"'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('manifestPlaceholders["appLabel"] = "Wambito"'));
    expect(_kotlin('../launch/LaunchLinks.kt'), contains('SCHEME = "wambito"'));
  });

  test('a cold start is night: the launch window and the Android 12 splash', () {
    const res = 'android/app/src/main/res';
    final colors = File('$res/values/colors.xml').readAsStringSync();
    final hex = RegExp(r'<color name="wambito_night_bg">#([0-9A-Fa-f]{6})</color>')
        .firstMatch(colors)!
        .group(1)!;
    expect(0xFF000000 | int.parse(hex, radix: 16), _argb(WambitoColors.night.bg));
    for (final file in ['drawable/launch_background.xml', 'drawable-v21/launch_background.xml']) {
      expect(File('$res/$file').readAsStringSync(), contains('@color/wambito_night_bg'));
    }
    final styles = File('$res/values/styles.xml').readAsStringSync();
    expect(styles, isNot(contains('Theme.Light')));
    expect(
      styles,
      contains('<item name="android:windowBackground">@color/wambito_night_bg</item>'),
    );
    expect(File('$res/values-night/styles.xml').existsSync(), isFalse, reason: 'one night theme');
    final splash = File('$res/values-v31/styles.xml').readAsStringSync();
    expect(
      splash,
      contains('<item name="android:windowSplashScreenBackground">@color/wambito_night_bg</item>'),
    );
    expect(
      splash,
      contains(
        '<item name="android:windowSplashScreenIconBackgroundColor">@color/wambito_night_bg</item>',
      ),
    );
  });

  test('the launcher icon is the adaptive Wambito coin, in the token colours', () {
    const res = 'android/app/src/main/res';
    expect(_manifest, contains('android:icon="@mipmap/ic_launcher"'));
    final adaptive = File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
    expect(adaptive, contains('<background android:drawable="@color/wambito_icon_bg" />'));
    expect(
      adaptive,
      contains('<foreground android:drawable="@drawable/ic_launcher_foreground" />'),
    );
    expect(
      adaptive,
      contains('<monochrome android:drawable="@drawable/ic_launcher_monochrome" />'),
    );
    final colors = File('$res/values/colors.xml').readAsStringSync();
    final bg = RegExp(r'<color name="wambito_icon_bg">#([0-9A-Fa-f]{6})</color>')
        .firstMatch(colors)!
        .group(1)!;
    expect(0xFF000000 | int.parse(bg, radix: 16), _argb(WambitoColors.day.brandPlum));
    final foreground = File('$res/drawable/ic_launcher_foreground.xml').readAsStringSync();
    expect(foreground, contains('android:fillColor="#${_hex(WambitoColors.day.brandGold)}"'));
    expect(foreground, contains('android:fillColor="#${_hex(WambitoColors.day.brandPlum)}"'));
    // The legacy launcher PNGs, one per density (48 dp).
    const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final MapEntry(key: density, value: px) in sizes.entries) {
      final png = File('$res/mipmap-$density/ic_launcher.png').readAsBytesSync();
      final header = ByteData.sublistView(png, 16, 24);
      expect([header.getUint32(0), header.getUint32(4)], [px, px], reason: density);
    }
  });

  test('the Quick Settings tile only the system can bind', () {
    expect(_manifest, contains('android:name=".tile.CaptureTileService"'));
    expect(_manifest, contains('android:permission="android.permission.BIND_QUICK_SETTINGS_TILE"'));
    expect(_manifest, contains('android.service.quicksettings.action.QS_TILE'));
  });
}
