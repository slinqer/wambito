import Flutter
import UIKit
import WambitoNative

/// The `wambito/device` channel: the phone's time zone, opening a web or mail link, the app's version, and keeping the vault out of backups.
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
      case "excludeFromBackup":
        // The vault's folder stays out of iCloud and device backups. `{path}`; true when set.
        guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
          result(false)
          return
        }
        result(BackupExclusion.exclude(path: path))
      case "appVersion":
        result(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
