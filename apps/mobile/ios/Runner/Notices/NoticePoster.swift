import Foundation
import UserNotifications
import WambitoNative

/// The words and the posting of the two notices. The words are `Notices.strings`, generated from the
/// Android string resources (scripts/gen-ios-strings.dart), in the language the app is set to.
enum NoticePoster {
  static let guestId = "wambito.notice.guest"
  /// "Hoy vence…" (DueTask.swift): one at a time, a new one replaces the last.
  static let dueId = "wambito.notice.due"
  /// The notification centre's title, the mascot's name (`notice_title` on Android).
  static let title = "Wambi"

  /// The app's own languages; anything else follows the phone.
  private static let languages: Set<String> = ["es", "en", "it", "pt"]

  /// [key] of `Notices.strings` in [language] (`es`, `en`, `it` or `pt`); the phone's language for
  /// any other (nil included). The key itself when the string is missing.
  static func text(_ key: String, language: String?) -> String {
    var bundle = Bundle.main
    if let language, languages.contains(language),
      let path = Bundle.main.path(forResource: language, ofType: "lproj"),
      let spoken = Bundle(path: path)
    {
      bundle = spoken
    }
    return bundle.localizedString(forKey: key, value: key, table: "Notices")
  }

  /// Puts the guest warning on the calendar [NoticeTimes.guestAfter] from now, replacing the one
  /// waiting. Nothing shows when the person has not allowed notices; the system decides at delivery.
  static func scheduleGuest(language: String?, center: UNUserNotificationCenter = .current()) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = text("notice_guest", language: language)
    content.sound = .default
    // The screen the warning is about: "Guarda tu progreso".
    content.userInfo = ["link": "progress"]
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: NoticeTimes.guestAfter, repeats: false)
    center.removePendingNotificationRequests(withIdentifiers: [guestId])
    center.add(UNNotificationRequest(identifier: guestId, content: content, trigger: trigger))
  }

  static func cancelGuest(center: UNUserNotificationCenter = .current()) {
    center.removePendingNotificationRequests(withIdentifiers: [guestId])
    center.removeDeliveredNotifications(withIdentifiers: [guestId])
  }
}
