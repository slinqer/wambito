import Flutter

/// The background run's channel `wambito/background` (lib/background/background_channel.dart), as
/// on Android (BackgroundChannel.kt):
///
///  * `finished({outcome, captured})` -> nil: the headless run ended. Nothing starts a headless
///    engine on iOS yet (a later task does), so there is nothing to hand the outcome to; it is
///    accepted and dropped.
///  * `vaultChanged()`, native -> Dart: a background run changed the vault file; see
///    [vaultChanged].
final class BackgroundChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/background", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "finished":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Tells the app's Dart a background run changed the vault file.
  func vaultChanged() {
    channel.invokeMethod("vaultChanged", arguments: nil)
  }
}
