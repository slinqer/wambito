// Port of apps/web/app/local/unlock-hint.test.ts: the "no PRF here" hint, per user, on this phone.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/settings/settings_store.dart';
import 'package:wambito/vault/unlock_hint.dart';

import '../settings/fakes.dart';

class _BrokenStore implements SettingsStore {
  @override
  Future<String?> read(String key) async => throw StateError('locked');

  @override
  Future<void> write(String key, String value) async => throw StateError('locked');

  @override
  Future<void> delete(String key) async => throw StateError('locked');
}

void main() {
  test('is false until noted, then true, under wambito.unlock.no_prf.<userId>', () async {
    final store = FakeSettingsStore();
    final hint = UnlockHint(store);
    expect(await hint.gaveNoPrf('user-1'), isFalse);
    await hint.noteWithoutPrf('user-1');
    expect(await hint.gaveNoPrf('user-1'), isTrue);
    expect(store.values, {'wambito.unlock.no_prf.user-1': '1'});
  });

  test('a passkey that opened the data clears it', () async {
    final hint = UnlockHint(FakeSettingsStore());
    await hint.noteWithoutPrf('user-1');
    await hint.noteOpened('user-1');
    expect(await hint.gaveNoPrf('user-1'), isFalse);
  });

  test('is per user: one account never marks or clears another', () async {
    final store = FakeSettingsStore();
    final hint = UnlockHint(store);
    await hint.noteWithoutPrf('user-1');
    expect(await hint.gaveNoPrf('user-2'), isFalse);
    await hint.noteWithoutPrf('user-2');
    await hint.noteOpened('user-2');
    expect(await hint.gaveNoPrf('user-1'), isTrue);
    await hint.forget('user-1');
    expect(store.values, isEmpty);
  });

  test('storage that fails reads false and never throws', () async {
    final hint = UnlockHint(_BrokenStore());
    expect(await hint.gaveNoPrf('user-1'), isFalse);
    await hint.noteWithoutPrf('user-1');
    await hint.noteOpened('user-1');
    await hint.forget('user-1');
  });
}
