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
///  * `scheduleDue({zone, language})` / `cancelDue` -> nil: "Hoy vence…", the daily background run
///    at 9:00 in the profile's zone (DueTask.swift); its settings are kept in `DueSettings`.
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
        let zone = DueSettings.store(
          zone: arguments?["zone"] as? String, language: arguments?["language"] as? String)
        DueTask.schedule(zone: zone)
        result(nil)
      case "cancelDue":
        DueSettings.clear()
        DueTask.cancel()
        // One already in the notification centre goes too: after a sign-out it names the previous
        // person's payments.
        self.center.removePendingNotificationRequests(withIdentifiers: [NoticePoster.dueId])
        self.center.removeDeliveredNotifications(withIdentifiers: [NoticePoster.dueId])
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
/// profile's zone, the language of the words, and the last day it was posted.
enum DueSettings {
  static let enabledKey = "wambito.notice.due.enabled"
  static let zoneKey = "wambito.notice.due.zone"
  static let languageKey = "wambito.notice.due.language"
  static let lastDayKey = "wambito.notice.due.lastDay"

  /// Switches the notice on. A nil [zone] keeps the one known (as `NoticeScheduler.scheduleDue` on
  /// Android); answers the zone the next run is aimed in (the phone's when none is known or the
  /// phone does not know it).
  @discardableResult
  static func store(zone: String?, language: String?, defaults: UserDefaults = .standard)
    -> TimeZone
  {
    let known = NoticeTimes.zone(zone ?? defaults.string(forKey: zoneKey), fallback: .current)
    defaults.set(true, forKey: enabledKey)
    if zone != nil { defaults.set(known.identifier, forKey: zoneKey) }
    defaults.set(language, forKey: languageKey)
    return known
  }

  static func clear(defaults: UserDefaults = .standard) {
    defaults.set(false, forKey: enabledKey)
    defaults.removeObject(forKey: zoneKey)
    defaults.removeObject(forKey: languageKey)
    // Another person, or the switch on again later, starts with no day recorded.
    defaults.removeObject(forKey: lastDayKey)
  }
}
