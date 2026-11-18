import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wambito/api/seen.dart';

class _MemorySeenStore implements SeenStore {
  final _days = <String, String>{};

  @override
  Future<String?> lastDay(String userId) async => _days[userId];

  @override
  Future<void> keep(String userId, String day) async => _days[userId] = day;
}

/// The app's once-a-day `/v2/me/seen` ping, answered at once with nothing sent: a test that is not
/// about it must not open a real connection when the app starts with a session.
Override quietSeenPing() => seenPingProvider.overrideWithValue(
  SeenPing(store: _MemorySeenStore(), post: () async {}, now: DateTime.now),
);
