// `hasQueued` on `wambito/capture`: an adoption asks it before wiping a deleted account's empty
// vault (lib/local/adopt.dart), so a queue Android cannot read must fail, never read as empty.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/capture_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wambito/capture');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('no Android side (iOS): nothing queued', () async {
    expect(await const ChannelAutoCapturePlatform().hasQueued('u1'), isFalse);
  });

  test('captures waiting for the account: true; none: false', () async {
    var captures = <Object?>[
      {'key': 'k1'},
    ];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takeQueued');
      expect(call.arguments, {'userId': 'u1'});
      return {'captures': captures, 'confirms': <Object?>[]};
    });
    expect(await const ChannelAutoCapturePlatform().hasQueued('u1'), isTrue);
    captures = [];
    expect(await const ChannelAutoCapturePlatform().hasQueued('u1'), isFalse);
  });

  test('Android could not read the queue: it throws, so the caller keeps the captures', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'io');
    });
    await expectLater(
      const ChannelAutoCapturePlatform().hasQueued('u1'),
      throwsA(isA<PlatformException>()),
    );
  });
}
