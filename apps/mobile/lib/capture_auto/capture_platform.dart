import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../home/home_cache.dart' show sessionOwnerOf;
import '../storage/secure_storage.dart';
import '../ui/lk_brand_logo.dart' show LkBrand;

import '../background/queued_capture.dart';

/// The sources automatic capture reads, by the wire name the Android side uses.
enum CaptureSource {
  revolut('revolut', 'Revolut', LkBrand.revolut),
  googleWallet('google_wallet', 'Google Wallet', LkBrand.googleWallet);

  const CaptureSource(this.wire, this.label, this.brand);

  final String wire;

  /// Its logo.
  final LkBrand brand;

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
  /// known one, are dropped) and what is left is sent. [from] is an account whose data [userId]
  /// takes over (a merge, or a merge called off): its captures are re-tagged and its "Bien"
  /// confirms kept, never dropped.
  Future<void> sendQueued(String userId, {String? from});

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

  /// Whether captures still wait in the queue for [userId] (read only): a deleted account's vault
  /// with some is adopted, never wiped (lib/local/adopt.dart). False where there is no queue (no
  /// Android side); throws when Android could not read it, so the caller keeps them.
  Future<bool> hasQueued(String userId);

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
  Future<void> sendQueued(String userId, {String? from}) =>
      _call<void>('sendQueued', {'userId': userId, 'from': ?from});

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
  Future<bool> hasQueued(String userId) async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMethod<Map<Object?, Object?>>('takeQueued', {'userId': userId});
    } on MissingPluginException {
      return false; // No Android side (iOS has no capture queue).
    }
    final captures = raw?['captures'];
    return captures is List && captures.isNotEmpty;
  }

  @override
  Future<void> ackQueued(List<String> keys, List<String> confirms) =>
      _call<void>('ackQueued', {'keys': keys, 'confirms': confirms});
}

/// The platform side of automatic capture (replaced in tests).
/// The captures a session takes over from another account (a merge's sign-in takes the guest's; its
/// cancel gives back what came in meanwhile), kept in secure storage `wambito.capture.handover` as
/// `{owner, from}` (owner: the hash of the new session's token, [sessionOwnerOf]) **before** that
/// token is written: a process killed in between still re-tags at the next start instead of
/// dropping. Every hand-over of the queue for that session (the session's, the preview sync's)
/// passes `from` until one went through ([done]).
class CaptureHandover {
  const CaptureHandover([this._storage = appSecureStorage]);

  static const key = 'wambito.capture.handover';

  final FlutterSecureStorage _storage;

  Future<void> keep(String token, String from) =>
      _storage.write(key: key, value: jsonEncode({'owner': sessionOwnerOf(token), 'from': from}));

  /// The account [token]'s session takes captures over from, or null.
  Future<String?> fromFor(String token) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return null;
      final doc = jsonDecode(raw);
      if (doc is! Map || doc['owner'] != sessionOwnerOf(token)) return null;
      final from = doc['from'];
      return from is String ? from : null;
    } on Object {
      return null;
    }
  }

  /// The hand-over for [token]'s session went through.
  Future<void> done(String token) async {
    try {
      if (await fromFor(token) != null) await _storage.delete(key: key);
    } on Object {
      // Re-tagging again later is harmless.
    }
  }
}

final captureHandoverProvider = Provider<CaptureHandover>((ref) => const CaptureHandover());

final autoCapturePlatformProvider = Provider<AutoCapturePlatform>(
  (ref) => const ChannelAutoCapturePlatform(),
);
