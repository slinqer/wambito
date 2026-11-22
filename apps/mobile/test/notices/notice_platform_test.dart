import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/notices/due_list.dart';
import 'package:wambito/notices/notice_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wambito/notices');
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? answer;

  setUp(() {
    calls.clear();
    answer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return answer?.call(call);
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('scheduling and cancelling go to Android by name, with the zone and the language', () async {
    const platform = ChannelNoticePlatform();
    await platform.scheduleDue(zone: 'America/Bogota', language: 'es');
    await platform.scheduleDue(zone: 'Asia/Tokyo', language: 'en');
    await platform.cancelDue();
    await platform.scheduleGuest(language: 'en');
    await platform.cancelGuest();

    expect(calls.map((c) => c.method), ['scheduleDue', 'scheduleDue', 'cancelDue', 'scheduleGuest', 'cancelGuest']);
    expect(calls[0].arguments, {'zone': 'America/Bogota', 'language': 'es'});
    expect(calls[1].arguments, {'zone': 'Asia/Tokyo', 'language': 'en'});
    expect(calls[3].arguments, {'language': 'en'});
  });

  test('the due list goes whole, with its owner, as days and names', () async {
    const platform = ChannelNoticePlatform();
    await platform.scheduleDueList(
      zone: 'America/Bogota',
      language: 'es',
      owner: 'u1',
      days: const [
        DueDay('2026-11-17', ['Arriendo', 'Gym']),
      ],
    );
    expect(calls.single.method, 'scheduleDueList');
    expect(calls.single.arguments, {
      'zone': 'America/Bogota',
      'language': 'es',
      'owner': 'u1',
      'days': [
        {
          'date': '2026-11-17',
          'names': ['Arriendo', 'Gym'],
        },
      ],
    });
  });

  test('the permission, as Android says it', () async {
    const platform = ChannelNoticePlatform();
    for (final (word, state) in [
      ('granted', NoticePermission.granted),
      ('askable', NoticePermission.askable),
      ('blocked', NoticePermission.blocked),
    ]) {
      answer = (_) => word;
      expect(await platform.permission(), state);
    }
    answer = (_) => 'something new';
    expect(await platform.permission(), NoticePermission.unavailable);
  });

  test('requesting it answers whether it was given', () async {
    const platform = ChannelNoticePlatform();
    answer = (_) => true;
    expect(await platform.requestPermission(), isTrue);
    answer = (_) => false;
    expect(await platform.requestPermission(), isFalse);
    answer = (_) => null;
    expect(await platform.requestPermission(), isFalse);
  });

  test('where there is no Android side the notices are unavailable and nothing throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    const platform = ChannelNoticePlatform();
    expect(await platform.permission(), NoticePermission.unavailable);
    await platform.scheduleDue(zone: 'UTC', language: 'es');
    await platform.cancelDue();
    await platform.scheduleGuest(language: 'es');
    await platform.cancelGuest();
    expect(await platform.requestPermission(), isFalse);
  });

  test('an error on the Android side is not the app\'s crash', () async {
    const platform = ChannelNoticePlatform();
    answer = (_) => throw PlatformException(code: 'boom');
    expect(await platform.permission(), NoticePermission.unavailable);
    await platform.scheduleGuest(language: 'es');
    expect(await platform.requestPermission(), isFalse);
  });
}
