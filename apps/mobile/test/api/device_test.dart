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
}
