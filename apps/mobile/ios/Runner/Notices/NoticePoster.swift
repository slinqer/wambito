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

  /// A `preview` account's "Hoy vence…": one local notification per day of [days] at 9:00 in [zone]
  /// ([DueSchedule]), in place of every `wambito.due.` request waiting (the list is replaced whole,
  /// never merged). Computed on the phone from the vault; the API is never asked. Nothing shows when
  /// the person has not allowed notices; the system decides at delivery.
  static func scheduleDueList(
    zone: TimeZone, language: String?, days: [(date: String, names: [String])],
    now: Date = Date(), center: UNUserNotificationCenter = .current()
  ) async {
    await cancelDueList(center: center)
    for request in DueSchedule.requests(days: days, zone: zone, now: now) {
      let body = DueToday.text(
        request.names,
        one: text("notice_due_one", language: language),
        many: text("notice_due_many", language: language),
        and: text("notice_and", language: language),
        andI: text("notice_and_i", language: language))
      guard !body.isEmpty else { continue }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      // Home, with the payments due today.
      content.userInfo = ["link": "due"]
      let trigger = UNCalendarNotificationTrigger(dateMatching: request.fire, repeats: false)
      try? await center.add(
        UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
    }
  }

  /// Removes every `wambito.due.` request, pending or already delivered: after a sign-out or an
  /// account change they name the previous person's payments.
  static func cancelDueList(center: UNUserNotificationCenter = .current()) async {
    let pending = await center.pendingNotificationRequests().map(\.identifier)
      .filter { $0.hasPrefix(DueSchedule.idPrefix) }
    center.removePendingNotificationRequests(withIdentifiers: pending)
    let delivered = await center.deliveredNotifications().map(\.request.identifier)
      .filter { $0.hasPrefix(DueSchedule.idPrefix) }
    center.removeDeliveredNotifications(withIdentifiers: delivered)
  }

  static func cancelGuest(center: UNUserNotificationCenter = .current()) {
    center.removePendingNotificationRequests(withIdentifiers: [guestId])
    center.removeDeliveredNotifications(withIdentifiers: [guestId])
  }
}
