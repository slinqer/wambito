import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/secure_storage.dart';

/// Where one on/off setting is kept. The app uses `flutter_secure_storage` (already in the app for
/// the session, so no new dependency); tests use memory.
abstract interface class FlagStore {
  /// Null when the person never chose.
  Future<bool?> read();
  Future<void> write(bool on);

  /// Forgets the choice: it reads as never made.
  Future<void> clear();
}

class SecureFlagStore implements FlagStore {
  const SecureFlagStore(this.key, [this._storage = appSecureStorage]);

  final String key;
  final FlutterSecureStorage _storage;

  @override
  Future<bool?> read() async => switch (await _storage.read(key: key)) {
    'off' => false,
    'on' => true,
    _ => null,
  };

  @override
  Future<void> write(bool on) => _storage.write(key: key, value: on ? 'on' : 'off');

  @override
  Future<void> clear() => _storage.delete(key: key);
}

/// The store of the setting kept under [key] (e.g. `setting.sound`). Tests replace it.
final flagStoreProvider = Provider.family<FlagStore, String>((ref, key) => SecureFlagStore(key));

/// An on/off setting kept on the phone and read back at the start. Until it has been read
/// ([ready]) it is not [active]: an effect the person turned off (a sound, a vibration) never
/// happens by mistake in the first moments. A choice made meanwhile wins. [state] is the choice
/// ([initial] until the person chooses); [active] is what the effect asks.
abstract class StoredFlag extends Notifier<bool> {
  var _chosen = false;
  var _loaded = false;
  var _ready = Future<void>.value();

  /// Where the choice is kept.
  FlagStore get store;

  /// The value until the person chooses.
  bool get initial;

  @override
  bool build() {
    _ready = _load();
    return initial;
  }

  Future<void> _load() async {
    try {
      final kept = await store.read();
      if (kept != null && !_chosen && ref.mounted) state = kept;
    } on Object {
      // Unreadable: the initial value stands.
    }
    _loaded = true;
  }

  /// Whether the setting is known and on.
  bool get active => _loaded && state;

  /// Completes once the kept choice has been read back (or found unreadable).
  Future<void> get ready => _ready;

  /// Turns the setting on or off, and keeps the choice. A store that cannot be written only means
  /// the choice is forgotten at the next start.
  Future<void> set(bool on) async {
    _chosen = true;
    _loaded = true;
    state = on;
    try {
      await store.write(on);
    } on Object {
      // Not kept.
    }
  }
}

/// Any of the on/off settings' providers.
typedef StoredFlagProvider = NotifierProvider<StoredFlag, bool>;
