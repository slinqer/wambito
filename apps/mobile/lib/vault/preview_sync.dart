import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/session.dart';
import '../capture_auto/capture_platform.dart';
import '../home/widget_sync.dart';
import 'encryption_mode.dart';

/// Where the account's mode is kept for the phone's own background jobs (Android's capture, widget
/// and due-notice workers, iOS's due-notice task), which call the API with the stored session
/// outside the app's finance guard. They read it first and do nothing that touches the API for a
/// `preview` account. Stored under `wambito.encryption.mode` (`plain`, `preview`, `unknown`;
/// absent when signed out), over the `wambito/notices` channel, which both phones have.
abstract interface class NativeEncryptionMode {
  /// Writes [mode], or clears it when null.
  Future<void> write(String? mode);
}

/// [NativeEncryptionMode] over `wambito/notices` `setEncryptionMode`. Where the channel does not
/// exist (tests, a desktop run) nothing is written; an error on the native side never reaches the
/// app.
class ChannelNativeEncryptionMode implements NativeEncryptionMode {
  const ChannelNativeEncryptionMode();

  static const _channel = MethodChannel('wambito/notices');

  @override
  Future<void> write(String? mode) async {
    try {
      await _channel.invokeMethod<void>('setEncryptionMode', {'mode': mode});
    } on MissingPluginException {
      // No native side.
    } on PlatformException {
      // The jobs keep what they had.
    }
  }
}

final nativeEncryptionModeProvider = Provider<NativeEncryptionMode>(
  (ref) => const ChannelNativeEncryptionMode(),
);

/// The native value for a standing: no session, none; a session whose account is not known yet,
/// `unknown` (the jobs wait); else the account's mode.
String? nativeModeOf(String? owner, EncryptionMode? mode) =>
    owner == null ? null : (mode?.name ?? 'unknown');

/// Keeps the phone's background jobs and the widget in step with the account's mode, for as long
/// as the app runs (app.dart watches it):
///  * the mode is written where the jobs read it ([NativeEncryptionMode]);
///  * the widget is told whether to draw figures ([WidgetSync.modeChanged]);
///  * the captures waiting to be sent are forgotten once the mode becomes `preview`
///    (`clearQueue`): nothing queued may go out, and the server would refuse it anyway (403).
final previewSyncProvider = Provider<void>((ref) {
  final native = ref.read(nativeEncryptionModeProvider);
  ({bool loading, String? owner, EncryptionMode? mode}) standing() => (
    loading: ref.read(sessionProvider).status == SessionStatus.loading,
    owner: ref.read(vaultOwnerProvider),
    mode: ref.read(currentVaultAccountProvider)?.mode,
  );
  void apply(EncryptionMode? before, ({bool loading, String? owner, EncryptionMode? mode}) now) {
    // While the stored session is being read nobody is known to be signed in or out: what the jobs
    // were told last stands (a `preview` account is never turned loose by a cold start).
    final written = now.loading
        ? Future<void>.value()
        : native.write(nativeModeOf(now.owner, now.mode)).catchError((Object _) {});
    ref.read(widgetSyncProvider).modeChanged(preview: now.mode == EncryptionMode.preview);
    if (now.mode == EncryptionMode.preview && before != EncryptionMode.preview) {
      // Read now, not after the native write: the container may be gone by then.
      final capture = ref.read(autoCapturePlatformProvider);
      // After the mode is written: the jobs already refuse before the queue is cleared.
      unawaited(
        written.then<void>(
          (_) => capture.clearQueue().then<void>((_) {}, onError: (Object _) {}),
        ),
      );
    } else {
      unawaited(written);
    }
  }

  var last = standing();
  apply(null, last);
  void check() {
    final now = standing();
    if (now == last) return;
    final before = last.mode;
    last = now;
    apply(before, now);
  }

  ref.listen(sessionProvider.select((s) => s.status), (_, _) => check());
  ref.listen(vaultOwnerProvider, (_, _) => check());
  ref.listen(currentVaultAccountProvider, (_, _) => check());
});
