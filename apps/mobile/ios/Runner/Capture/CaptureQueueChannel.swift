import Flutter
import WambitoNative

/// The headless engine's `wambito/capture` (Android's CaptureQueueChannel.kt): `captureMain` reads
/// the queue and acknowledges what it saved. It only answers from the queue: a failed run keeps all.
///
///  * `takeQueued({userId})` -> `{captures: [...], confirms: [txId]}`.
///  * `ackQueued({keys, confirms})` -> nil.
final class CaptureQueueChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger, store: CaptureQueueStore = .standard()) {
    channel = FlutterMethodChannel(name: "wambito/capture", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      result(CaptureQueueChannel.answer(call, store: store) ?? FlutterMethodNotImplemented)
    }
  }

  /// The queue's two methods, shared with the app's engine (CaptureChannel); nil for any other.
  /// A method that answers nothing answers `NSNull`.
  static func answer(_ call: FlutterMethodCall, store: CaptureQueueStore) -> Any? {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "takeQueued":
      guard let userId = arguments?["userId"] as? String else {
        return FlutterError(code: "bad_args", message: "userId", details: nil)
      }
      let taken = store.takeForRun(userId: userId)
      return ["captures": taken.captures, "confirms": taken.confirms]
    case "ackQueued":
      store.ack(
        keys: arguments?["keys"] as? [String] ?? [],
        confirms: arguments?["confirms"] as? [String] ?? [])
      return NSNull()
    default:
      return nil
    }
  }

  func close() {
    channel.setMethodCallHandler(nil)
  }
}
