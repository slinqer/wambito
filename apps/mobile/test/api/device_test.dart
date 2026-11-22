import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/device.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('the client header says ios on an iPhone', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(DeviceHints.fallback.headers['x-wambito-client'], 'ios');
  });

  test('the client header says android everywhere else', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(DeviceHints.fallback.headers['x-wambito-client'], 'android');
    debugDefaultTargetPlatformOverride = null;
    expect(DeviceHints.fallback.headers['x-wambito-client'], 'android');
  });

  test('x-wambito-version carries the app version; a version with a space is not sent', () {
    const ok = DeviceHints(timezone: 'UTC', locale: 'es', appVersion: '1.2.3+4');
    expect(ok.headers['x-wambito-version'], '1.2.3+4');
    const bad = DeviceHints(timezone: 'UTC', locale: 'es', appVersion: '1.2 3');
    expect(bad.headers.containsKey('x-wambito-version'), isFalse);
    expect(DeviceHints.fallback.headers.containsKey('x-wambito-version'), isFalse);
  });
}
