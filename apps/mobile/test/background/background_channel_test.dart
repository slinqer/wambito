import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/background/background_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wambito/background');

  Future<void> fromNative(String method) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  test('vaultChanged reaches the listener until it is removed', () async {
    var calls = 0;
    final remove = const BackgroundListener().listen(() => calls++);
    await fromNative('vaultChanged');
    expect(calls, 1);

    remove();
    await fromNative('vaultChanged');
    expect(calls, 1);
  });
}
