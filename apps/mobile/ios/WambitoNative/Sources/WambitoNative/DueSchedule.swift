import Foundation

/// The local notifications of a `preview` account's "Hoy vence…" (spec section 7.2): the app (and the
/// headless run) read the next days' payments from the vault and hand them over as days and names
/// (`wambito/notices` `scheduleDueList`); iOS posts one notice per day at 9:00 in the profile's zone.
/// The twin of `DueList.kt` and `DueWorker` on Android. The API is never asked.
public enum DueSchedule {
  /// The prefix of every request's identifier: a new list removes the pending ones first, and a
  /// sign-out or an account change (`cancelDue`) removes them all.
  public static let idPrefix = "wambito.due."

  /// The 9:00 of each day in [days] (`YYYY-MM-DD` and the names due on it) in [zone], skipping the
  /// days with no name and the 9:00 that is not after [now] (today's, once it has passed). The
  /// identifier is `wambito.due.<date>`; [fire] carries [zone], so a clock change still lands on
  /// 9:00 local.
  public static func requests(
    days: [(date: String, names: [String])], zone: TimeZone, now: Date
  ) -> [(id: String, fire: DateComponents, names: [String])] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return days.compactMap { day in
      let parts = day.date.split(separator: "-").compactMap { Int($0) }
      let names = day.names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      guard parts.count == 3, day.date.count == 10, !names.isEmpty else { return nil }
      let fire = DateComponents(
        calendar: calendar, timeZone: zone, year: parts[0], month: parts[1], day: parts[2],
        hour: 9, minute: 0)
      guard let at = calendar.date(from: fire), at > now else { return nil }
      return (id: idPrefix + day.date, fire: fire, names: names)
    }
  }

  /// The identifiers among [ids] that are due requests (`wambito.due.` prefix), and no other notice.
  public static func dueIds(_ ids: [String]) -> [String] { ids.filter { $0.hasPrefix(idPrefix) } }

  /// Whether a list read for [owner] may be scheduled while [current] is the account the app last
  /// told the phone about (`AccountMode.owner`): both must be known and equal. Closes the race where
  /// a headless run hands a list over after a sign-out or an account change.
  public static func accepts(owner: String?, current: String?) -> Bool {
    guard let owner, let current else { return false }
    return owner == current
  }
}
