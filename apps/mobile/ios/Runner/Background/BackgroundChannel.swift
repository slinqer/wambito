import Flutter

/// The background run's channel `wambito/background` (lib/background/background_channel.dart), as
/// on Android (BackgroundChannel.kt):
///
///  * `finished({outcome, captured})` -> nil: the headless run ended. On the headless engine
///    [onFinished] is handed the outcome and the answers of the captures it saved (HeadlessRunner,
///    CaptureRun); on the app's engine there is none and it is accepted and dropped. Nothing on this
///    side sends anything, whatever the outcome.
///  * `vaultChanged()`, native -> Dart: a background run changed the vault file; see
///    [vaultChanged].
final class BackgroundChannel {
  /// The app's own engine's channel while it lives, where `vaultChanged` goes (main thread only).
  static weak var app: BackgroundChannel?

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger, onFinished: ((String, [[String: Any]]) -> Void)? = nil) {
    channel = FlutterMethodChannel(name: "wambito/background", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "finished":
        let arguments = call.arguments as? [String: Any]
        onFinished?(
          arguments?["outcome"] as? String ?? "failed",
          arguments?["captured"] as? [[String: Any]] ?? [])
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

  /// Stops listening (the headless engine is about to be destroyed).
  func close() {
    channel.setMethodCallHandler(nil)
  }
}
