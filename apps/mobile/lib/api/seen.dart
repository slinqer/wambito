import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/secure_storage.dart';
import '../vault/encryption_mode.dart' show vaultAccountProvider;
import 'session.dart' show networkClientProvider;

/// The last local day this phone told the server the account was opened, per account.
abstract interface class SeenStore {
  Future<String?> lastDay(String userId);
  Future<void> keep(String userId, String day);
}

/// [SeenStore] over `flutter_secure_storage`, key `wambito.seen.<userId>`.
class SecureSeenStore implements SeenStore {
  const SecureSeenStore([this._storage = appSecureStorage]);

  final FlutterSecureStorage _storage;

  static String keyOf(String userId) => 'wambito.seen.$userId';

  @override
  Future<String?> lastDay(String userId) => _storage.read(key: keyOf(userId));

  @override
  Future<void> keep(String userId, String day) => _storage.write(key: keyOf(userId), value: day);
}

/// Tells the server, at most once per local day and account, that the person opened the app
/// (`POST /v2/me/seen`: the daily activity numbers). The day is kept only after a 2xx; every error
/// is swallowed, so the next foreground tries again. Only the app calls it, never a headless run.
class SeenPing {
  SeenPing({required this.store, required this.post, required this.now});

  final SeenStore store;
  final Future<void> Function() post;
  final DateTime Function() now;
  final _inFlight = <String>{};

  Future<void> foreground(String userId) async {
    if (!_inFlight.add(userId)) return;
    try {
      final today = _day(now());
      if (await store.lastDay(userId) == today) return;
      await post();
      await store.keep(userId, today);
    } catch (_) {
      // Nothing is kept: the next foreground tries again.
    } finally {
      _inFlight.remove(userId);
    }
  }

  static String _day(DateTime t) {
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  }
}

final seenPingProvider = Provider<SeenPing>(
  (ref) => SeenPing(
    store: const SecureSeenStore(),
    post: () async {
      await ref.read(networkClientProvider).api.getDefaultApi().markSeen();
    },
    now: DateTime.now,
  ),
);

/// Pings once the session's account is known and on every resume (app.dart watches it).
final seenSyncProvider = Provider<void>((ref) {
  final ping = ref.watch(seenPingProvider);
  final userId = ref.watch(vaultAccountProvider.select((a) => a.value?.profile.id));
  if (userId == null) return;
  unawaited(ping.foreground(userId));
  final observer = _ResumeObserver(() => unawaited(ping.foreground(userId)));
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});

/// A plain observer, not an [AppLifecycleListener]: that one asserts on a lifecycle jump (paused to
/// resumed) which the app's tests make.
class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResume);

  final void Function() _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }
}
