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
