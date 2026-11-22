import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'due_list.dart';

/// Whether Android lets the app post notices.
enum NoticePermission {
  /// Notices can be posted.
  granted,

  /// Not yet: Android 13+ asks, and the app may (lib/notices/notice_sync.dart asks once).
  askable,

  /// Switched off in the phone's settings; the app cannot change that.
  blocked,

  /// No Android side to ask (tests, other platforms): the notices do nothing.
  unavailable,
}

/// Android's side of the two local notices (spec section 7.2), `android/.../notices/`: the jobs on
/// WorkManager that post them, and the notification permission. Tests replace it.
abstract interface class NoticePlatform {
  /// Schedules "Hoy vence…" for the next 9:00 in [zone] (the profile's IANA zone). Scheduling
  /// again keeps the job already waiting for the same zone.
  Future<void> scheduleDue({required String zone, required String language});

  /// A `preview` account's "Hoy vence…": the next [days] (computed from the vault, never asked of
  /// the server) handed to the phone for [owner], the account they were read for, and the daily
  /// notice scheduled as [scheduleDue] does. Replaces the whole list each time, never merges.
  /// Native code posts nothing when [owner] is not the account it was last told about.
  Future<void> scheduleDueList({
    required String zone,
    required String language,
    required String owner,
    required List<DueDay> days,
  });

  /// Cancels the notice and clears the due list, on both phones.
  Future<void> cancelDue();

  /// Sets the guest warning 44 days from now, in place of any earlier one.
  Future<void> scheduleGuest({required String language});

  Future<void> cancelGuest();

  Future<NoticePermission> permission();

  /// Android's own prompt (13+); whether it was allowed. Only the app asks, on screen.
  Future<bool> requestPermission();
}

/// [NoticePlatform] over the `wambito/notices` channel (NoticesChannel.kt). Where that channel does
/// not exist the notices are [NoticePermission.unavailable] and nothing is scheduled; an error on
/// the Android side never reaches the app.
class ChannelNoticePlatform implements NoticePlatform {
  const ChannelNoticePlatform();

  static const _channel = MethodChannel('wambito/notices');

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> scheduleDue({required String zone, required String language}) =>
      _call<void>('scheduleDue', {'zone': zone, 'language': language});

  @override
  Future<void> scheduleDueList({
    required String zone,
    required String language,
    required String owner,
    required List<DueDay> days,
  }) => _call<void>('scheduleDueList', {
    'zone': zone,
    'language': language,
    'owner': owner,
    'days': [for (final d in days) d.toJson()],
  });

  @override
  Future<void> cancelDue() => _call<void>('cancelDue');

  @override
  Future<void> scheduleGuest({required String language}) =>
      _call<void>('scheduleGuest', {'language': language});

  @override
  Future<void> cancelGuest() => _call<void>('cancelGuest');

  @override
  Future<NoticePermission> permission() async => switch (await _call<String>('permission')) {
    'granted' => NoticePermission.granted,
    'askable' => NoticePermission.askable,
    'blocked' => NoticePermission.blocked,
    _ => NoticePermission.unavailable,
  };

  @override
  Future<bool> requestPermission() async => await _call<bool>('requestPermission') ?? false;
}

/// The platform side of the notices (replaced in tests).
final noticePlatformProvider = Provider<NoticePlatform>((ref) => const ChannelNoticePlatform());
