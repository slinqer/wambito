import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('backup is off: the Keystore-bound session token cannot be restored on another device', () {
    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('the microphone is asked for (quick capture), and no Google speech service is used', () {
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    final kotlin = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    expect(kotlin, contains('org.vosk'));
    // Android's SpeechRecognizer sends audio to whichever service the phone has: Google's, mostly.
    expect(kotlin, isNot(contains('SpeechRecognizer')));
  });

  test('the motor is asked for (the haptics), and sounds play without Play Services', () {
    expect(manifest, contains('android.permission.VIBRATE'));
    final kotlin = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    // Composition primitives on Android 11 and up, a waveform below (spec section 6.2).
    expect(kotlin, contains('VibrationEffect.startComposition'));
    expect(kotlin, contains('areAllPrimitivesSupported'));
    expect(kotlin, contains('createWaveform'));
    // The platform's own SoundPool: no audio plugin, nothing from Google.
    expect(kotlin, contains('SoundPool'));
  });

  test('the QR scanner: CAMERA is optional hardware, and its activity is not exported', () {
    expect(manifest, contains('android.permission.CAMERA'));
    // A phone with no camera still installs the app (the typed code stays).
    expect(
      manifest,
      contains('<uses-feature android:name="android.hardware.camera" android:required="false"/>'),
    );
    final activity = RegExp(r'<activity\s[^>]*\.scanner\.ScannerActivity[^>]*/>')
        .firstMatch(manifest)!
        .group(0)!;
    expect(activity, contains('android:exported="false"'));
    // The preview's transform assumes a portrait screen: a rotation would distort it.
    expect(activity, contains('android:screenOrientation="portrait"'));
    // Only the app's own channel starts it: no intent filter on it, and no Google scanner anywhere.
    expect(activity, isNot(contains('intent-filter')));
    final kotlin = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    expect(kotlin, contains('com.google.zxing'));
    expect(kotlin, isNot(contains('mlkit')));
  });

  test(
    'the notices: POST_NOTIFICATIONS, and the due link comes only through the not-exported alias',
    () {
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      // Exactly one place may start the app on wambito://due: the alias that is not exported.
      final alias = RegExp(r'<activity-alias[^>]*LaunchLinkAlias[\s\S]*?</activity-alias>')
          .firstMatch(manifest)!
          .group(0)!;
      expect(alias, contains('android:exported="false"'));
      expect(alias, contains('android:host="due"'));
      expect(alias.split('android:host="due"').length - 1, 1);
      expect(manifest.split('android:host="due"').length - 1, 1);
      final schemes = RegExp(r'android:scheme="([^"]+)"').allMatches(manifest).map((m) => m[1]);
      expect(schemes.toSet(), {'wambito', 'https'});
      expect(alias, contains('android:scheme="wambito" android:host="due"'));
      // No Firebase, no push receiver: both notices are scheduled on the phone.
      expect(manifest, isNot(contains('firebase')));
      expect(manifest, isNot(contains('com.google.android.c2dm')));
    },
  );

  test('manifest declares CaptureListener with the bind permission, and asks for nothing new', () {
    final service = RegExp(r'<service[^>]*\.capture\.CaptureListener[\s\S]*?</service>')
        .firstMatch(manifest)!
        .group(0)!;
    expect(service, contains('android:exported="true"'));
    expect(
      service,
      contains('android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"'),
    );
    expect(service, contains('android.service.notification.NotificationListenerService'));
    // Bound through its service permission: no uses-permission line for it.
    expect(
      manifest,
      isNot(contains('<uses-permission android:name="android.permission.BIND_NOTIFICATION')),
    );
  });

  test(
    'the web sign-in QR: host signin once, on the exported MainActivity, never on the alias',
    () {
      expect(manifest.split('android:host="signin"').length - 1, 1);
      final main = RegExp(r'<activity\s[^>]*android:name="\.MainActivity"[\s\S]*?</activity>')
          .firstMatch(manifest)!
          .group(0)!;
      expect(main, contains('android:exported="true"'));
      expect(main, contains('<data android:scheme="wambito" android:host="signin"/>'));
      // the system camera opens it: a browsable VIEW filter of its own
      final filter = RegExp(
        r'<intent-filter>(?:(?!</intent-filter>)[\s\S])*android:host="signin"[\s\S]*?</intent-filter>',
      ).firstMatch(main)!.group(0)!;
      expect(filter, contains('android.intent.action.VIEW'));
      expect(filter, contains('android.intent.category.BROWSABLE'));
      // nothing else of the app's own links rides on it
      expect(RegExp('android:host=').allMatches(filter), hasLength(1));
      final alias = RegExp(r'<activity-alias[^>]*LaunchLinkAlias[\s\S]*?</activity-alias>')
          .firstMatch(manifest)!
          .group(0)!;
      expect(alias, isNot(contains('signin')));
    },
  );
}
