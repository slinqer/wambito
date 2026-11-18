import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/seen.dart';
import 'package:wambito/api/session.dart' show sessionProvider;

import '../entry/fakes.dart' show mockStorage;
import '../support/plain_account.dart';

class _Store implements SeenStore {
  final days = <String, String>{};

  @override
  Future<String?> lastDay(String userId) async => days[userId];

  @override
  Future<void> keep(String userId, String day) async => days[userId] = day;
}

void main() {
  late _Store store;
  late DateTime now;
  late int posts;
  late bool fail;
  late SeenPing ping;

  setUp(() {
    store = _Store();
    now = DateTime(2026, 11, 18, 9);
    posts = 0;
    fail = false;
    ping = SeenPing(
      store: store,
      post: () async {
        posts++;
        if (fail) throw StateError('500');
      },
      now: () => now,
    );
  });

  test('first foreground of the day posts once', () async {
    await ping.foreground('u1');
    expect(posts, 1);
    expect(store.days['u1'], '2026-11-18');
  });

  test('a second foreground the same day posts nothing', () async {
    await ping.foreground('u1');
    now = DateTime(2026, 11, 18, 23, 59);
    await ping.foreground('u1');
    expect(posts, 1);
  });

  test('the next local day posts again', () async {
    await ping.foreground('u1');
    now = DateTime(2026, 11, 19, 0, 1);
    await ping.foreground('u1');
    expect(posts, 2);
    expect(store.days['u1'], '2026-11-19');
  });

  test('a failed post keeps nothing, so the next foreground tries again', () async {
    fail = true;
    await ping.foreground('u1');
    expect(store.days, isEmpty);
    fail = false;
    await ping.foreground('u1');
    expect(posts, 2);
    expect(store.days['u1'], '2026-11-18');
  });

  test('another account the same day posts for it too', () async {
    await ping.foreground('u1');
    await ping.foreground('u2');
    expect(posts, 2);
  });

  test('a plain account posts once a day too', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockStorage(token: 'tok');
    final container = ProviderContainer(
      overrides: [
        plainAccount(id: 'plain-1'),
        seenPingProvider.overrideWithValue(ping),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider);
    container.listen(seenSyncProvider, (_, _) {});
    for (var i = 0; i < 20 && posts == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(posts, 1);
    expect(store.days['plain-1'], '2026-11-18');
    // The resume of the app the same day posts nothing more.
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(posts, 1);
  });
}
