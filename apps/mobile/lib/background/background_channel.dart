import 'package:flutter/services.dart';

import 'background_run.dart';

/// The headless engine's side of `wambito/background` (Android `background/`, iOS
/// `BackgroundChannel.swift`): it tells native code how the run ended.
class BackgroundChannel {
  const BackgroundChannel();

  static const _channel = MethodChannel('wambito/background');

  /// `finished {outcome, captured}`: [BackgroundReport.outcome] by its name, and the answers of the
  /// local `POST /v1/captures` for the notifications. An error on the native side never reaches
  /// the run.
  Future<void> finished(BackgroundReport report) async {
    try {
      await _channel.invokeMethod<void>('finished', {
        'outcome': report.outcome.name,
        'captured': report.captured,
      });
    } on MissingPluginException {
      // No native side (tests, a plain Dart run).
    } on PlatformException {
      // See above.
    }
  }
}

/// The app's side of `wambito/background` (D7): native code says a headless run changed the vault
/// file (`vaultChanged`). One listener at a time; [listen] returns what removes it.
class BackgroundListener {
  const BackgroundListener();

  static const _channel = MethodChannel('wambito/background');

  void Function() listen(void Function() onVaultChanged) {
    Future<Object?> handle(MethodCall call) async {
      if (call.method == 'vaultChanged') {
        onVaultChanged();
        return null;
      }
      throw MissingPluginException(call.method);
    }

    _channel.setMethodCallHandler(handle);
    return () => _channel.setMethodCallHandler(null);
  }
}
