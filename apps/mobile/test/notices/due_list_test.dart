// The due list a `preview` account's notices are scheduled from: computed from the vault.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/backend.dart';
import 'package:wambito/local/memory_store.dart';
import 'package:wambito/notices/due_list.dart';

void main() {
  late LocalBackend backend;
  late String food;
  var tick = 0;

  Future<Map<Object?, Object?>> call(String method, String path, [Object? body]) async {
    final res = await backend.handle(method, path, const {}, body);
    return ((res!.body ?? const {}) as Map).cast<Object?, Object?>();
  }

  Future<String> rule(String name, int day, {String start = '2026-09-01'}) async {
    final made = await call('POST', '/v1/recurrences', {
      'name': name,
      'amount': -50000000,
      'categoryId': food,
      'frequency': 'monthly',
      'dayOfMonth': day,
      'startDate': start,
    });
    return made['id']! as String;
  }

  setUp(() async {
    backend = createLocalBackend(
      store: createMemoryStore(),
      // Each reading of the clock is a second later: the rows have distinct creation times.
      now: () => DateTime.utc(2026, 10, 28, 15).add(Duration(seconds: tick++)),
      timezone: 'America/Bogota',
      profile: const LocalProfile(id: 'u1', encryption: 'preview'),
    );
    await call('PATCH', '/v1/me', {
      'currency': 'COP',
      'locale': 'es',
      'timezone': 'America/Bogota',
      'onboardingCompleted': true,
    });
    food =
        (await call('POST', '/v1/categories', {
              'name': 'Food',
              'kind': 'expense',
              'icon': 'fork',
              'color': '#f90',
            }))['id']!
            as String;
  });

  test(
    'a rule due on the 3rd and the 17th gives both days in a window crossing the month end',
    () async {
      await rule('Arriendo', 3);
      await rule('Gym', 17);
      final days = await dueDays(backend, today: '2026-10-28', days: 14);
      expect([for (final d in days) d.date], ['2026-11-03']);
      expect(days.single.names, ['Arriendo']);

      final wide = await dueDays(backend, today: '2026-10-28', days: 30);
      expect([for (final d in wide) d.date], ['2026-11-03', '2026-11-17']);
      expect(wide.last.names, ['Gym']);
    },
  );

  test('days outside the window, and movements with no rule, are left out', () async {
    await rule('Arriendo', 3);
    await call('POST', '/v1/transactions', {
      'name': 'Cafe',
      'amount': -1000000,
      'categoryId': food,
      'date': '2026-10-30',
      'status': 'pending',
    });
    final days = await dueDays(backend, today: '2026-10-28', days: 3);
    expect(days, isEmpty);
    final week = await dueDays(backend, today: '2026-10-29', days: 14);
    expect(week.expand((d) => d.names), ['Arriendo']);
  });

  test('today is part of the window and the names come in creation order', () async {
    await rule('Zeta', 28);
    await rule('Alfa', 28);
    final days = await dueDays(backend, today: '2026-10-28');
    expect(days.single.date, '2026-10-28');
    expect(days.single.names, ['Zeta', 'Alfa']);
  });

  test('a deleted rule disappears', () async {
    final id = await rule('Arriendo', 3);
    await rule('Gym', 5);
    expect((await dueDays(backend, today: '2026-10-28')).expand((d) => d.names), [
      'Arriendo',
      'Gym',
    ]);
    await call('DELETE', '/v1/recurrences/$id');
    expect((await dueDays(backend, today: '2026-10-28')).expand((d) => d.names), ['Gym']);
  });

  test('toJson is the channel shape', () {
    expect(const DueDay('2026-11-03', ['A']).toJson(), {
      'date': '2026-11-03',
      'names': ['A'],
    });
  });
}
