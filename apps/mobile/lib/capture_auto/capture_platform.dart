import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/queued_capture.dart';

/// The sources automatic capture reads, by the wire name the Android side uses.
enum CaptureSource {
  revolut('revolut', 'Revolut'),
  googleWallet('google_wallet', 'Google Wallet');

  const CaptureSource(this.wire, this.label);

  final String wire;

  /// The app's own name: the same in every language.
  final String label;
}

/// What Android says about automatic capture: whether the notification access is granted, and the
/// sources the person switched on (wire names, see [CaptureSource]).
class AutoCaptureStatus {
  const AutoCaptureStatus({required this.access, required this.sources});

  final bool access;
  final Set<String> sources;

  bool isOn(CaptureSource source) => sources.contains(source.wire);

  bool get anyOn => sources.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is AutoCaptureStatus && other.access == access && _same(other.sources, sources);

  @override
  int get hashCode => Object.hash(access, Object.hashAllUnordered(sources));

  static bool _same(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
}

/// Android's side of automatic capture (spec section 2.1), `android/.../capture/CaptureChannel.kt`:
/// which sources are on, the notification access, and the queue of captures waiting to be sent.
/// Tests replace it.
abstract interface class AutoCapturePlatform {
  /// The state, or null where there is no Android side (tests, other platforms): the section hides.
  Future<AutoCaptureStatus?> status();

  Future<void> setSource(String source, bool enabled);

  /// Android's notification access screen; whether it opened.
  Future<bool> openAccessSettings();

  /// The app's info screen (where "Allow restricted settings" is); whether it opened.
  Future<bool> openAppInfo();

  /// Forgets the captures waiting to be sent (on sign-out: they belong to the old account).
  Future<void> clearQueue();

  /// [userId] signed in: the queue becomes theirs (captures queued for another account, or for no
  /// known one, are dropped) and what is left is sent.
  Future<void> sendQueued(String userId);

  /// Takes away the phone notifications of [ids]: they were confirmed in the app.
  Future<void> dismissNotifications(List<String> ids);

  /// [ids] is everything still to review, as read when [before] began: the notifications of any
  /// other detected transaction (confirmed on the web, through an assistant, in the editor) go.
  /// One posted from [before] on may be newer than the list, so it stays.
  Future<void> keepOnlyNotifications(List<String> ids, DateTime before);

  /// What waits in the queue for [userId]'s vault, for the headless engine (`captureMain`): the
  /// parsed captures (each with its stable `key`) and the notification ids confirmed with "Bien".
  /// Nothing is removed until [ackQueued].
  Future<({List<QueuedCapture> captures, List<String> confirms})> takeQueued(String userId);

  /// The engine saved these captures (by `key`) and applied these confirms: they leave the queue.
  Future<void> ackQueued(List<String> keys, List<String> confirms);
}

/// [AutoCapturePlatform] over the `wambito/capture` channel. Where that channel does not exist the
/// status is null; an error on the Android side never reaches the app.
class ChannelAutoCapturePlatform implements AutoCapturePlatform {
  const ChannelAutoCapturePlatform();

  static const _channel = MethodChannel('wambito/capture');

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
  Future<AutoCaptureStatus?> status() async {
    final raw = await _call<Map<Object?, Object?>>('status');
    if (raw == null) return null;
    final sources = raw['sources'];
    return AutoCaptureStatus(
      access: raw['access'] == 'granted',
      sources: {if (sources is List) ...sources.whereType<String>()},
    );
  }

  @override
  Future<void> setSource(String source, bool enabled) =>
      _call<void>('setSource', {'source': source, 'enabled': enabled});

  @override
  Future<bool> openAccessSettings() async => await _call<bool>('openAccessSettings') ?? false;

  @override
  Future<bool> openAppInfo() async => await _call<bool>('openAppInfo') ?? false;

  @override
  Future<void> clearQueue() => _call<void>('clearQueue');

  @override
  Future<void> sendQueued(String userId) => _call<void>('sendQueued', {'userId': userId});

  @override
  Future<void> dismissNotifications(List<String> ids) => _call<void>('dismiss', {'ids': ids});

  @override
  Future<void> keepOnlyNotifications(List<String> ids, DateTime before) =>
      _call<void>('keepOnly', {'ids': ids, 'before': before.millisecondsSinceEpoch});

  @override
  Future<({List<QueuedCapture> captures, List<String> confirms})> takeQueued(String userId) async {
    final raw = await _call<Map<Object?, Object?>>('takeQueued', {'userId': userId});
    final captures = <QueuedCapture>[];
    for (final item in (raw?['captures'] as List?) ?? const []) {
      try {
        if (item is Map) captures.add(QueuedCapture.fromJson(item));
      } on FormatException {
        // Kept in the queue by native code; never saved.
      }
    }
    final confirms = [...((raw?['confirms'] as List?) ?? const []).whereType<String>()];
    return (captures: captures, confirms: confirms);
  }

  @override
  Future<void> ackQueued(List<String> keys, List<String> confirms) =>
      _call<void>('ackQueued', {'keys': keys, 'confirms': confirms});
}

/// The platform side of automatic capture (replaced in tests).
final autoCapturePlatformProvider = Provider<AutoCapturePlatform>(
  (ref) => const ChannelAutoCapturePlatform(),
);
