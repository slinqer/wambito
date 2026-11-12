import Flutter
import UIKit
import WambitoNative

/// The `wambito/device` channel: the phone's time zone, opening a web or mail link, and the app's version.
/// Same methods and answers as the Android side (MainActivity.kt).
final class DeviceChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/device", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "timeZone":
        result(TimeZone.current.identifier)
      case "openUrl":
        // True when the phone took the address; any other kind of address is refused.
        guard let address = call.arguments as? String, ExternalLinks.isOpenable(address),
          let url = URL(string: address)
        else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      case "appVersion":
        result(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
