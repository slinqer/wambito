import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/vault_gate.dart';
import 'package:wambito/vault/vault_onboarding.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../entry/fakes.dart';
import '../home/fakes.dart';
import '../protect/fakes.dart';

/// A session kept on the phone whose writes fail (the Keystore refuses).
class _FailingWrites extends SessionStore {
  @override
  Future<StoredSession?> read() async =>
      const StoredSession(token: 'tok', guest: false, onboardingPending: true);

  @override
  Future<void> write(
    String token, {
    required bool guest,
    bool onboardingPending = false,
    bool onboardingKnown = true,
  }) async => throw PlatformException(code: 'keystore');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a vault answer the session cannot keep still ends the wait: the start never stays on '
      'the loading route', () async {
    mockStorage(token: 'tok');
    final vault = FakeVault(onboardingCompletedAt: '2026-11-01T12:00:00.000Z');
    await vault.seeded;
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(FakeAuthApi()),
        passkeysProvider.overrideWithValue(FakePasskeys()),
        widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
        homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
        sessionStoreProvider.overrideWithValue(_FailingWrites()),
        vaultGateStateProvider.overrideWithValue(Ready<VaultSession>(vault)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).ready;
    container.listen(vaultOnboardingProvider, (_, _) {});
    for (var i = 0; i < 20 && container.read(vaultOnboardingProvider) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(vaultOnboardingProvider), isFalse);
    // This start follows the vault, although it could not be kept.
    expect(container.read(sessionProvider).onboardingPending, isFalse);
  });
}
