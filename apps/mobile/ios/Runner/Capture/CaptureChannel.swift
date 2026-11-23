import Flutter
import UIKit
import UserNotifications
import WambitoNative

/// The app's `wambito/capture` on the iPhone (lib/capture_auto/capture_platform.dart), the twin of
/// Android's CaptureChannel.kt (spec 2026-11-22-ios-wallet-capture-design.md, section 3.2):
///
///  * `status` -> null below iOS 17 (no Transaction automation: the section hides), else
///    `{access: "granted", sources, available: ["apple_wallet"], configured, iosMajor}`.
///  * `setSource({source, enabled})` -> nil: the Apple Pay switch.
///  * `openAccessSettings` / `openAppInfo` -> false: Android only.
///  * `clearQueue` -> nil (sign-out). `sendQueued({userId, from?})` -> nil: adopt, then save.
///  * `takeQueued({userId})` / `ackQueued({keys, confirms})`: as the headless engine's.
///  * `dismiss({ids})` / `keepOnly({ids, before})` -> nil: the capture notifications of transactions
///    confirmed elsewhere go.
///  * `test({body})` -> true: "Probar", [body] posted as a payment's notification, nothing saved.
///  * `openShortcuts` -> whether the Shortcuts app opened.
final class CaptureChannel {
  private let channel: FlutterMethodChannel
  private let store: CaptureQueueStore
  private let center = UNUserNotificationCenter.current()

  init(messenger: FlutterBinaryMessenger, store: CaptureQueueStore = .standard()) {
    self.store = store
    channel = FlutterMethodChannel(name: "wambito/capture", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      self.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "status":
      result(Self.status())
    case "setSource":
      guard arguments?["source"] as? String == CaptureSettings.wallet,
        let enabled = arguments?["enabled"] as? Bool
      else {
        result(FlutterError(code: "bad_args", message: "source, enabled", details: nil))
        return
      }
      CaptureSettings.setWallet(enabled)
      result(nil)
    case "openAccessSettings", "openAppInfo":
      result(false)
    case "clearQueue":
      store.clear()
      result(nil)
    case "sendQueued":
      guard let userId = arguments?["userId"] as? String else {
        result(FlutterError(code: "bad_args", message: "userId", details: nil))
        return
      }
      store.adopt(userId: userId, from: arguments?["from"] as? String)
      CaptureRun.send()
      result(nil)
    case "dismiss":
      let ids = (arguments?["ids"] as? [String] ?? []).map(CaptureAnswer.noticeId)
      center.removeDeliveredNotifications(withIdentifiers: ids)
      result(nil)
    case "keepOnly":
      let keep = Set((arguments?["ids"] as? [String] ?? []).map(CaptureAnswer.noticeId))
      // `before` is in milliseconds since the epoch.
      let millis = (arguments?["before"] as? NSNumber)?.doubleValue ?? 0
      let cutoff = Date(timeIntervalSince1970: millis / 1000)
      center.getDeliveredNotifications { [center] delivered in
        let gone = delivered.filter {
          $0.request.identifier.hasPrefix("wambito.capture.")
            && !keep.contains($0.request.identifier) && $0.date < cutoff
        }.map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: gone)
      }
      result(nil)
    case "openShortcuts":
      guard let url = URL(string: "shortcuts://") else {
        result(false)
        return
      }
      UIApplication.shared.open(url) { result($0) }
    case "test":
      guard let body = arguments?["body"] as? String, !body.isEmpty else {
        result(FlutterError(code: "bad_args", message: "body", details: nil))
        return
      }
      CaptureRun.test(body)
      result(true)
    default:
      let answer = CaptureQueueChannel.answer(call, store: store)
      result(answer is NSNull ? nil : (answer ?? FlutterMethodNotImplemented))
    }
  }

  /// What `status` answers.
  static func status() -> [String: Any]? {
    guard #available(iOS 17, *) else { return nil }
    return [
      "access": "granted",
      "sources": CaptureSettings.walletOn() ? [CaptureSettings.wallet] : [String](),
      "available": [CaptureSettings.wallet],
      "configured": CaptureSettings.configured(),
      "iosMajor": ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
    ]
  }
}
