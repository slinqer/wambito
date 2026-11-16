import AVFoundation
import Flutter
import UIKit
import WambitoNative

/// The QR scanner, on the `wambito/scanner` channel (lib/scanner/qr_scanner.dart), as on Android
/// (scanner/ScannerChannel.kt). The camera is only ever opened by `scan`, and its permission only
/// asked there.
///
///  * `isAvailable` -> true when the phone has a camera.
///  * `scan` -> the text of the first `wambito://pair?` QR read (`ScannerViewController`, full
///    screen), or nil when the person closed it or refused the camera permission (no error). Failures:
///    `busy` (a scan is already open), `failed` (the camera could not start, or nothing to present on).
///
/// One scan at a time, and every path answers the call exactly once.
final class ScannerChannel: NSObject {
  private let channel: FlutterMethodChannel
  private var pending: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/scanner", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "isAvailable":
        result(AVCaptureDevice.default(for: .video) != nil)
      case "scan":
        self.scan(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func scan(_ result: @escaping FlutterResult) {
    guard pending == nil else {
      return result(FlutterError(code: "busy", message: "A scan is already open", details: nil))
    }
    pending = result
    switch CameraAccess.state(AVCaptureDevice.authorizationStatus(for: .video).rawValue) {
    case "granted":
      present()
    case "ask":
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          if granted { self?.present() } else { self?.finish(nil) }
        }
      }
    default:
      // Denied or restricted: nothing to say; the typed code stays.
      finish(nil)
    }
  }

  private func present() {
    guard let top = Self.topViewController() else {
      return fail("failed", "Nothing to show the camera on")
    }
    let scanner = ScannerViewController { [weak self] outcome in
      switch outcome {
      case .text(let text): self?.finish(text)
      case .cancelled: self?.finish(nil)
      case .failed: self?.fail("failed", "The camera could not start")
      }
    }
    scanner.modalPresentationStyle = .fullScreen
    top.present(scanner, animated: true)
  }

  private func finish(_ text: String?) {
    guard let result = pending else { return }
    pending = nil
    result(text)
  }

  private func fail(_ code: String, _ message: String) {
    guard let result = pending else { return }
    pending = nil
    result(FlutterError(code: code, message: message, details: nil))
  }

  /// The view controller on top of the app's windows, where a full-screen camera can be presented.
  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
