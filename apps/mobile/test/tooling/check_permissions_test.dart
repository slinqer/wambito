import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// scripts/check-permissions.sh, fed a recorded `aapt2 dump permissions` output instead of a built
/// APK (CI runs it for real on the release APK).
Future<ProcessResult> _check(String dump) async {
  final dir = await Directory.systemTemp.createTemp('check-permissions');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/permissions.txt')..writeAsStringSync(dump);
  return Process.run('bash', ['scripts/check-permissions.sh', '--dump', file.path]);
}

const _receiver = '''
permission: com.wambito.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='com.wambito.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
''';

/// The microphone, for quick capture's on-phone speech engine (Task 12).
const _mic = "uses-permission: name='android.permission.RECORD_AUDIO'\n";

/// The motor, for the haptics (Task 13). A normal permission: nothing is asked of the person.
/// With it, the two WorkManager needs for the widget's refresh job (Task 15): waiting for a
/// network, and scheduling again after a restart. Normal permissions too. And the two local
/// notices' (Task 16), the one that is asked at runtime on Android 13+.
const _vibrate =
    "uses-permission: name='android.permission.VIBRATE'\n"
    "uses-permission: name='android.permission.ACCESS_NETWORK_STATE'\n"
    "uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'\n"
    "uses-permission: name='android.permission.POST_NOTIFICATIONS'\n"
    // The QR scanner's camera (Task 14), asked at scan time.
    "uses-permission: name='android.permission.CAMERA'\n";

void main() {
  test('release permissions: INTERNET, RECORD_AUDIO, VIBRATE and the AndroidX receiver permission pass', () async {
    final result = await _check(
      'package: com.wambito.app\n'
      "uses-permission: name='android.permission.INTERNET'\n$_mic$_vibrate$_receiver",
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });

  test('release permissions: no INTERNET fails (the app could not reach its server)', () async {
    final result = await _check('package: com.wambito.app\n$_mic$_vibrate$_receiver');
    expect(result.exitCode, 1);
    expect(result.stdout, contains('android.permission.INTERNET'));
  });

  test('release permissions: no RECORD_AUDIO fails (quick capture could never listen)', () async {
    final result = await _check(
      'package: com.wambito.app\n'
      "uses-permission: name='android.permission.INTERNET'\n$_vibrate$_receiver",
    );
    expect(result.exitCode, 1);
    expect(result.stdout, contains('android.permission.RECORD_AUDIO'));
  });

  test('release permissions: no VIBRATE fails (the haptics would be silent)', () async {
    final result = await _check(
      'package: com.wambito.app\n'
      "uses-permission: name='android.permission.INTERNET'\n$_mic$_receiver",
    );
    expect(result.exitCode, 1);
    expect(result.stdout, contains('android.permission.VIBRATE'));
  });

  for (final needed in ['ACCESS_NETWORK_STATE', 'RECEIVE_BOOT_COMPLETED']) {
    test('release permissions: no $needed fails (the widget refresh job needs it)', () async {
      final without = _vibrate.split('\n').where((line) => !line.contains(needed)).join('\n');
      final result = await _check(
        'package: com.wambito.app\n'
        "uses-permission: name='android.permission.INTERNET'\n$_mic$without\n$_receiver",
      );
      expect(result.exitCode, 1);
      expect(result.stdout, contains('android.permission.$needed'));
    });
  }

  test(
    'release permissions: no POST_NOTIFICATIONS fails (the two local notices could never post)',
    () async {
      final without = _vibrate
          .split('\n')
          .where((line) => !line.contains('POST_NOTIFICATIONS'))
          .join('\n');
      final result = await _check(
        'package: com.wambito.app\n'
        "uses-permission: name='android.permission.INTERNET'\n$_mic$without\n$_receiver",
      );
      expect(result.exitCode, 1);
      expect(result.stdout, contains('Missing permission: android.permission.POST_NOTIFICATIONS'));
    },
  );

  test(
    'release permissions: no CAMERA fails (the QR of a new device could never be scanned)',
    () async {
      final without = _vibrate.split('\n').where((line) => !line.contains('CAMERA')).join('\n');
      final result = await _check(
        'package: com.wambito.app\n'
        "uses-permission: name='android.permission.INTERNET'\n$_mic$without\n$_receiver",
      );
      expect(result.exitCode, 1);
      expect(result.stdout, contains('Missing permission: android.permission.CAMERA'));
    },
  );

  for (final unwanted in ['WAKE_LOCK', 'FOREGROUND_SERVICE']) {
    test("release permissions: WorkManager's $unwanted stays out", () async {
      final result = await _check(
        'package: com.wambito.app\n'
        "uses-permission: name='android.permission.INTERNET'\n"
        "uses-permission: name='android.permission.$unwanted'\n$_mic$_vibrate$_receiver",
      );
      expect(result.exitCode, 1);
      expect(result.stdout, contains('Unexpected permission: android.permission.$unwanted'));
    });
  }

  test('release permissions: an unexpected permission fails with its name', () async {
    final result = await _check(
      'package: com.wambito.app\n'
      "uses-permission: name='android.permission.INTERNET'\n"
      "uses-permission: name='com.google.android.gms.permission.AD_ID'\n$_mic$_vibrate$_receiver",
    );
    expect(result.exitCode, 1);
    expect(result.stdout, contains('com.google.android.gms.permission.AD_ID'));
  });

  test('release permissions: a missing APK is an error, not a pass', () async {
    final result = await Process.run('bash', [
      'scripts/check-permissions.sh',
      '--apk',
      '/nonexistent/app-release.apk',
    ]);
    expect(result.exitCode, 2);
  });
}
