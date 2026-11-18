import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/scanner/qr_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wambito/scanner');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        return 'wambito://pair?id=x';
      },
    );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('scan asks for the pairing QR by default, and for the prefixes it is given', () async {
    await const MethodQrScanner().scan();
    await const MethodQrScanner().scan(prefixes: const [signinQrPrefix]);
    expect(calls.map((c) => c.method), ['scan', 'scan']);
    expect(calls[0].arguments, {
      'prefixes': ['wambito://pair?'],
    });
    expect(calls[1].arguments, {
      'prefixes': ['wambito://signin?'],
    });
  });
}
