import Flutter
import UIKit
import UserNotifications
import WambitoNative

/// The app's hand on the two notices (lib/notices/notice_platform.dart), on the `wambito/notices`
/// method channel, as on Android (NoticesChannel.kt):
///
///  * `permission` -> `granted` (notices can be posted), `askable` (the app may ask) or `blocked`
///    (switched off in the phone's settings, which the app cannot change).
///  * `requestPermission` -> true when notices are allowed after the system prompt.
///  * `scheduleGuest({language})` / `cancelGuest` -> nil: the guest warning, 44 days from now.
///  * `scheduleDue({zone, language})` / `cancelDue` -> nil: for now only stored (`DueSettings`); the
///    daily "Hoy vence…" run reads them.
final class NoticesChannel {
  private let channel: FlutterMethodChannel
  private let center = UNUserNotificationCenter.current()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/notices", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "scheduleDue":
        DueSettings.store(
          zone: arguments?["zone"] as? String, language: arguments?["language"] as? String)
        result(nil)
      case "cancelDue":
        DueSettings.clear()
        result(nil)
      case "scheduleGuest":
        NoticePoster.scheduleGuest(language: arguments?["language"] as? String, center: self.center)
        result(nil)
      case "cancelGuest":
        NoticePoster.cancelGuest(center: self.center)
        result(nil)
      case "permission":
        self.center.getNotificationSettings { settings in
          let answer = NoticesChannel.permission(settings.authorizationStatus)
          DispatchQueue.main.async { result(answer) }
        }
      case "requestPermission":
        self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// `.notDetermined` is the only state the app can still ask in; `.denied` only the phone's
  /// settings can change. Authorized, provisional and ephemeral all let notices through.
  static func permission(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "askable"
    case .denied: return "blocked"
    default: return "granted"
    }
  }
}

/// What `scheduleDue` was given, kept for the daily run that posts "Hoy vence…": switched on, the
/// profile's zone and the language of the words.
enum DueSettings {
  static let enabledKey = "wambito.notice.due.enabled"
  static let zoneKey = "wambito.notice.due.zone"
  static let languageKey = "wambito.notice.due.language"

  static func store(zone: String?, language: String?, defaults: UserDefaults = .standard) {
    defaults.set(true, forKey: enabledKey)
    defaults.set(zone, forKey: zoneKey)
    defaults.set(language, forKey: languageKey)
  }

  static func clear(defaults: UserDefaults = .standard) {
    defaults.set(false, forKey: enabledKey)
    defaults.removeObject(forKey: zoneKey)
    defaults.removeObject(forKey: languageKey)
  }
}
