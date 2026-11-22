import 'package:wambito/local/backend.dart';
import 'package:wambito/local/memory_store.dart';

/// An invented vault of account `u1` (COP, Bogota): one lunch of 50 000 pesos spent on 2026-10-21.
Future<LocalBackend> seededVaultBackend(DateTime now) async {
  final backend = createLocalBackend(
    store: createMemoryStore(),
    now: () => now,
    timezone: 'America/Bogota',
    profile: const LocalProfile(id: 'u1', encryption: 'preview'),
  );
  Future<Map<Object?, Object?>> call(String method, String path, Object? body) async {
    final res = await backend.handle(method, path, const {}, body);
    return (res!.body! as Map).cast<Object?, Object?>();
  }

  await call('PATCH', '/v1/me', {
    'currency': 'COP',
    'locale': 'es',
    'timezone': 'America/Bogota',
    'onboardingCompleted': true,
  });
  final food = await call('POST', '/v1/categories', {
    'name': 'Food',
    'kind': 'expense',
    'icon': 'fork',
    'color': '#f90',
  });
  await call('POST', '/v1/transactions', {
    'name': 'Lunch',
    'amount': -5000000,
    'categoryId': food['id'],
    'date': '2026-10-21',
  });
  return backend;
}
