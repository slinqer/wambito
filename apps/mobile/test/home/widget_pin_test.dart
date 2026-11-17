import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/home/widget_pin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wambito/device');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('each method returns what the phone answers', () async {
    final answers = {'widgetInstalled': true, 'widgetPinSupported': false, 'pinWidget': true};
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return answers[call.method];
    });
    final pin = WidgetPin();
    expect(await pin.installed(), isTrue);
    expect(await pin.supported(), isFalse);
    expect(await pin.pin(), isTrue);
    expect(calls, ['widgetInstalled', 'widgetPinSupported', 'pinWidget']);
  });

  test('no handler gives false for all three', () async {
    final pin = WidgetPin();
    expect(await pin.installed(), isFalse);
    expect(await pin.supported(), isFalse);
    expect(await pin.pin(), isFalse);
  });

  test('a platform error gives false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'x'));
    final pin = WidgetPin();
    expect(await pin.installed(), isFalse);
    expect(await pin.pin(), isFalse);
  });
}
