import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/capture_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wambito/capture');
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? answer;

  setUp(() {
    calls.clear();
    answer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        return answer?.call(call);
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  test('the status is read as Android says it', () async {
    const platform = ChannelAutoCapturePlatform();
    answer = (_) => {
      'access': 'granted',
      'sources': ['revolut'],
    };
    final status = await platform.status();
    expect(status?.access, isTrue);
    expect(status?.sources, {'revolut'});

    answer = (_) => {'access': 'missing', 'sources': <String>[]};
    final missing = await platform.status();
    expect(missing?.access, isFalse);
    expect(missing?.anyOn, isFalse);
  });

  test('the iPhone says which sources it has, whether one arrived and its iOS version', () async {
    const platform = ChannelAutoCapturePlatform();
    answer = (_) => {
      'access': 'granted',
      'sources': ['apple_wallet'],
      'available': ['apple_wallet'],
      'configured': true,
      'iosMajor': 27,
    };
    final status = await platform.status();
    expect(status?.available, {'apple_wallet'});
    expect(status?.configured, isTrue);
    expect(status?.iosMajor, 27);
    expect(status?.isOn(CaptureSource.appleWallet), isTrue);
  });

  test('Android lists no sources: they are Revolut, Google Wallet and ActivoBank', () async {
    const platform = ChannelAutoCapturePlatform();
    answer = (_) => {'access': 'granted', 'sources': <String>[]};
    final status = await platform.status();
    expect(status?.available, {'revolut', 'google_wallet', 'activobank'});
    expect(status?.configured, isFalse);
    expect(status?.iosMajor, isNull);
  });

  test('Android offers Google Wallet first, then Revolut and ActivoBank', () {
    expect(const AutoCaptureStatus(access: true, sources: {}).offered, [
      CaptureSource.googleWallet,
      CaptureSource.revolut,
      CaptureSource.activobank,
    ]);
  });

  test('switching a source, opening the screens and clearing the queue go by name', () async {
    const platform = ChannelAutoCapturePlatform();
    answer = (call) => call.method.startsWith('open') ? true : null;
    await platform.setSource('google_wallet', true);
    expect(await platform.openAccessSettings(), isTrue);
    expect(await platform.openAppInfo(), isTrue);
    await platform.clearQueue();

    expect(calls.map((c) => c.method), [
      'setSource',
      'openAccessSettings',
      'openAppInfo',
      'clearQueue',
    ]);
    expect(calls.first.arguments, {'source': 'google_wallet', 'enabled': true});
  });

  test('sendQueued names the account the queue now belongs to', () async {
    const platform = ChannelAutoCapturePlatform();
    await platform.sendQueued('user-1');
    expect(calls.single.method, 'sendQueued');
    expect(calls.single.arguments, {'userId': 'user-1'});
  });

  test('sendQueued names the account a merge takes the captures from', () async {
    const platform = ChannelAutoCapturePlatform();
    await platform.sendQueued('user-1', from: 'anon-1');
    expect(calls.single.arguments, {'userId': 'user-1', 'from': 'anon-1'});
  });

  test('without an Android side the status is null and nothing throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    const platform = ChannelAutoCapturePlatform();
    expect(await platform.status(), isNull);
    expect(await platform.openAccessSettings(), isFalse);
    await platform.clearQueue();
  });

  test('the queue is taken for the account and acknowledged by key and id', () async {
    const platform = ChannelAutoCapturePlatform();
    answer = (call) => call.method == 'takeQueued'
        ? {
            'captures': [
              {
                'key': 'k1',
                'kind': 'expense',
                'amount': 1250,
                'currency': 'EUR',
                'merchant': 'Mercadona',
                'capturedAt': '2026-11-04T15:00:00.000Z',
                'source': 'revolut',
              },
              {'key': 'bad'},
            ],
            'confirms': ['tx-1'],
          }
        : null;
    final taken = await platform.takeQueued('user_1');
    expect(calls.last.method, 'takeQueued');
    expect(calls.last.arguments, {'userId': 'user_1'});
    expect(taken.captures.map((c) => c.key), ['k1'], reason: 'a malformed item is skipped');
    expect(taken.confirms, ['tx-1']);

    await platform.ackQueued(['k1'], ['tx-1']);
    expect(calls.last.method, 'ackQueued');
    expect(calls.last.arguments, {
      'keys': ['k1'],
      'confirms': ['tx-1'],
    });
  });

  test('without a native side the queue is empty', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    final taken = await const ChannelAutoCapturePlatform().takeQueued('user_1');
    expect(taken.captures, isEmpty);
    expect(taken.confirms, isEmpty);
  });
}
