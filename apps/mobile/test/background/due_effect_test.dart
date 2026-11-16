// The `due` effect of a background run: the due list handed to the phone, owner-checked.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/background/due_effect.dart';
import 'package:wambito/local/backend.dart';
import 'package:wambito/local/memory_store.dart';

import 'package:wambito/notices/notice_platform.dart';

import '../notices/fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28, 15);
  late FakeNoticePlatform platform;
  late LocalBackend backend;

  setUp(() async {
    platform = FakeNoticePlatform(permissionState: NoticePermission.granted);
    backend = createLocalBackend(
      store: createMemoryStore(),
      now: () => now,
      timezone: 'America/Bogota',
      profile: const LocalProfile(id: 'u1', encryption: 'preview'),
    );
    Future<Map<Object?, Object?>> call(String m, String p, Object? b) async =>
        ((await backend.handle(m, p, const {}, b))!.body! as Map).cast();
    await call('PATCH', '/v1/me', {
      'currency': 'COP',
      'locale': 'es',
      'timezone': 'America/Bogota',
      'onboardingCompleted': true,
    });
    final food = (await call('POST', '/v1/categories', {
      'name': 'Food',
      'kind': 'expense',
      'icon': 'fork',
      'color': '#f90',
    }))['id'];
    await call('POST', '/v1/recurrences', {
      'name': 'Arriendo',
      'amount': -50000000,
      'categoryId': food,
      'frequency': 'monthly',
      'dayOfMonth': 30,
      'startDate': '2026-09-01',
    });
  });

  Future<void> Function(String, LocalBackend) effect({bool on = true, bool owns = true}) =>
      dueEffect(
        platform: platform,
        enabled: () async => on,
        language: 'es',
        now: () => now,
        owns: (_) async => owns,
      );

  test('hands the list to the phone with its owner', () async {
    await effect()('u1', backend);
    expect(platform.callsNamed('scheduleDueList'), ['scheduleDueList America/Bogota es u1']);
    expect(platform.dueLists.single.single.names, ['Arriendo']);
  });

  test('the switch off cancels it', () async {
    await effect(on: false)('u1', backend);
    expect(platform.calls, ['cancelDue']);
  });

  test('another account, or a session gone, hands nothing over', () async {
    await effect(owns: false)('u1', backend);
    expect(platform.calls, isEmpty);
  });

  test('notices not allowed cancel the list', () async {
    platform.permissionState = NoticePermission.blocked;
    await effect()('u1', backend);
    expect(platform.calls, ['cancelDue']);
  });
}
