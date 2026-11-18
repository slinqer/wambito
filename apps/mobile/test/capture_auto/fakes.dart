import 'package:wambito/background/queued_capture.dart';
import 'package:wambito/capture_auto/capture_platform.dart';

/// Android's side of automatic capture in memory.
class FakeAutoCapturePlatform implements AutoCapturePlatform {
  FakeAutoCapturePlatform({this.access = false, Set<String>? sources, this.available = true})
    : sources = sources ?? {};

  /// Whether the notification access is granted.
  bool access;
  final Set<String> sources;

  /// False: no Android side (the status is null).
  bool available;

  /// Every call, in order: `setSource revolut true`, `openAccessSettings`, ...
  final calls = <String>[];

  List<String> callsNamed(String name) => calls.where((c) => c.split(' ').first == name).toList();

  @override
  Future<AutoCaptureStatus?> status() async {
    calls.add('status');
    return available ? AutoCaptureStatus(access: access, sources: {...sources}) : null;
  }

  @override
  Future<void> setSource(String source, bool enabled) async {
    calls.add('setSource $source $enabled');
    if (enabled) {
      sources.add(source);
    } else {
      sources.remove(source);
    }
  }

  @override
  Future<bool> openAccessSettings() async {
    calls.add('openAccessSettings');
    return true;
  }

  @override
  Future<bool> openAppInfo() async {
    calls.add('openAppInfo');
    return true;
  }

  @override
  Future<void> clearQueue() async => calls.add('clearQueue');

  @override
  Future<void> sendQueued(String userId, {String? from}) async =>
      calls.add(from == null ? 'sendQueued $userId' : 'sendQueued $userId from $from');

  /// The `before` of each [keepOnlyNotifications], in order.
  final keepBefore = <DateTime>[];

  @override
  Future<void> dismissNotifications(List<String> ids) async =>
      calls.add('dismiss ${ids.join(',')}');

  @override
  Future<void> keepOnlyNotifications(List<String> ids, DateTime before) async {
    calls.add('keepOnly ${ids.join(',')}');
    keepBefore.add(before);
  }

  /// What [takeQueued] hands out.
  List<QueuedCapture> queuedCaptures = [];
  List<String> queuedConfirms = [];

  @override
  Future<({List<QueuedCapture> captures, List<String> confirms})> takeQueued(String userId) async {
    calls.add('takeQueued $userId');
    return (captures: [...queuedCaptures], confirms: [...queuedConfirms]);
  }

  /// What [hasQueued] throws when set (Android could not read the queue).
  Object? hasQueuedError;

  @override
  Future<bool> hasQueued(String userId) async {
    calls.add('hasQueued $userId');
    final error = hasQueuedError;
    if (error != null) throw error;
    return queuedCaptures.isNotEmpty;
  }

  @override
  Future<void> ackQueued(List<String> keys, List<String> confirms) async =>
      calls.add('ackQueued ${keys.join(',')} | ${confirms.join(',')}');
}
