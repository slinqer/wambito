import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/backend.dart' show LocalBackend, createLocalBackend;
import 'package:wambito/local/memory_store.dart';
import 'package:wambito/local/store.dart';
import 'package:wambito/local/sync.dart' show SyncResult;
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/settings/passkeys_settings.dart';
import 'package:wambito/vault/encryption_mode.dart';

const settingsId = '01930000-0000-7000-8000-0000000000f1';

/// The seeded settings record of a vault.
Map<String, Object?> seededSettings({String? recoveryKeySavedAt, String? onboardingCompletedAt}) =>
    {
      's': 1,
      'name': null,
      'currency': 'EUR',
      'locale': 'es',
      'timezone': 'America/Bogota',
      'onboardingCompletedAt': onboardingCompletedAt,
      'revokedDevices': <Object?>[],
      'recoveryKeySavedAt': recoveryKeySavedAt,
    };

/// An open vault on a memory store with its settings record; counts its syncs and key reloads.
class FakeVault implements VaultSession {
  FakeVault({String? recoveryKeySavedAt, String? onboardingCompletedAt, this.userId = 'user-1'})
    : store = createMemoryStore() {
    seeded = store.put(
      RecordType.settings,
      settingsId,
      seededSettings(
        recoveryKeySavedAt: recoveryKeySavedAt,
        onboardingCompletedAt: onboardingCompletedAt,
      ),
    );
  }

  @override
  final String userId;

  @override
  final FinanceStore store;

  late final Future<void> seeded;
  int syncs = 0;
  int reloads = 0;

  @override
  LocalBackend get backend => createLocalBackend(store: store, now: DateTime.now);

  @override
  Future<int> pendingChanges() async => 0;

  @override
  Future<SyncResult> sync() async {
    syncs += 1;
    return SyncResult();
  }

  @override
  Future<void> reloadKeys() async {
    reloads += 1;
  }

  @override
  void Function() subscribe(void Function() listener) => store.subscribe(listener);

  Future<Object?> savedAt() async =>
      (await store.get(RecordType.settings, settingsId))!.body['recoveryKeySavedAt'];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The account as `GET /v1/me` says it, known now.
Override accountOf({bool anonymous = true, EncryptionMode mode = EncryptionMode.preview}) =>
    currentVaultAccountProvider.overrideWithValue(
      VaultAccount(
        owner: 'owner-1',
        profile: VaultProfile(
          id: 'user-1',
          email: anonymous ? '' : 'ana@wambito.test',
          isAnonymous: anonymous,
          locale: 'es',
          timezone: 'America/Bogota',
        ),
        mode: mode,
      ),
    );

/// The account's passkeys, and what adding one does.
class FakeSettingsPasskeys implements SettingsPasskeys {
  FakeSettingsPasskeys([List<PasskeyItem>? items]) : items = items ?? [];

  final List<PasskeyItem> items;
  PasskeyPrfUse? used;
  PasskeyOutcome answer = PasskeyOutcome.added;

  @override
  Future<bool> supported() async => true;

  @override
  Future<List<PasskeyItem>> list() async => items;

  @override
  Future<PasskeyOutcome> add({PasskeyPrfUse? prf}) async {
    used = prf;
    return answer;
  }

  @override
  Future<void> remove(String id) async {}
}

PasskeyItem passkeyItem(String credentialId) => PasskeyItem(
  id: 'pk-$credentialId',
  credentialId: credentialId,
  createdAt: DateTime.utc(2026, 11, 2, 9),
);
