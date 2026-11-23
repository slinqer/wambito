import Foundation
import UserNotifications
import WambitoNative

/// The silent "Anoté −$18.000 en Juan Valdez · Café, ¿bien?" per saved payment (spec 2026-11-22,
/// section 3.3), the twin of Android's CapturePoster: category `wambito.capture` with **Bien**
/// (confirms in the background) and **Cambiar** (opens `wambito://review/<id>`). One notification per
/// transaction (`CaptureAnswer.noticeId`), so a merged answer replaces it.
enum CaptureNotices {
  /// Persistent names: automations and pending notifications point at them.
  static let category = "wambito.capture"
  static let testCategory = "wambito.capture.test"
  static let confirmAction = "wambito.capture.ok"
  static let changeAction = "wambito.capture.change"

  /// The language the app last told the native side (the notices' setting), else the phone's.
  private static var language: String? {
    UserDefaults.standard.string(forKey: DueSettings.languageKey)
  }

  /// The categories with their two buttons; called at launch (and again costs nothing).
  static func register(center: UNUserNotificationCenter = .current()) {
    let ok = UNNotificationAction(
      identifier: confirmAction, title: NoticePoster.text("capture_confirm", language: language),
      options: [])
    let change = UNNotificationAction(
      identifier: changeAction, title: NoticePoster.text("capture_change", language: language),
      options: [.foreground])
    center.getNotificationCategories { existing in
      let others = existing.filter { $0.identifier != category && $0.identifier != testCategory }
      center.setNotificationCategories(
        others.union([
          UNNotificationCategory(identifier: category, actions: [ok, change], intentIdentifiers: []),
          UNNotificationCategory(identifier: testCategory, actions: [], intentIdentifiers: []),
        ]))
    }
  }

  /// A run's answers: one already confirmed goes away, the rest are posted.
  static func announce(_ answers: [CaptureAnswer], center: UNUserNotificationCenter = .current()) {
    var seen = Set<String>()
    for answer in answers where seen.insert(answer.id).inserted {
      if answer.merged && !answer.needsReview {
        center.removeDeliveredNotifications(withIdentifiers: [CaptureAnswer.noticeId(answer.id)])
      } else {
        post(answer, category: category, center: center)
      }
    }
  }

  /// "Probar": the notification a payment would bring, with the invented one Dart wrote in [body]
  /// (in the app's language); nothing is queued or saved, and it has no buttons.
  static func test(body: String, center: UNUserNotificationCenter = .current()) {
    post(id: "test", body: body, category: testCategory, center: center)
  }

  private static func post(
    _ answer: CaptureAnswer, category: String, center: UNUserNotificationCenter
  ) {
    let body = answer.noted(
      template: NoticePoster.text("capture_noted", language: language),
      fallbackTemplate: NoticePoster.text("capture_noted_fallback", language: language),
      language: language ?? "es")
    post(id: answer.id, body: body, category: category, center: center)
  }

  private static func post(
    id: String, body: String, category: String, center: UNUserNotificationCenter
  ) {
    let content = UNMutableNotificationContent()
    content.title = NoticePoster.title
    content.body = body
    // Wallet already chimed: this one is silent.
    content.sound = nil
    if #available(iOS 15, *) { content.interruptionLevel = .passive }
    content.threadIdentifier = Self.category
    content.categoryIdentifier = category
    content.userInfo = category == testCategory ? [:] : ["link": "review/\(id)", "transactionId": id]
    center.add(
      UNNotificationRequest(identifier: CaptureAnswer.noticeId(id), content: content, trigger: nil))
  }

  /// **Bien** on [transactionId]'s notification: confirm it at the next run, run now, and take the
  /// notification away once the run applied it. [done] is called when the work is over.
  static func confirm(
    _ transactionId: String, store: CaptureQueueStore = .standard(),
    center: UNUserNotificationCenter = .current(), done: @escaping () -> Void
  ) {
    store.addConfirm(transactionId)
    CaptureRun.send(store: store) { _ in
      if let owner = store.owner, !store.take(userId: owner).confirms.contains(transactionId) {
        center.removeDeliveredNotifications(withIdentifiers: [CaptureAnswer.noticeId(transactionId)])
      }
      done()
    }
  }
}
