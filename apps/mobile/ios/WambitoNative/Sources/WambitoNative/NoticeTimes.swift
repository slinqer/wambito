import Foundation

/// When the two notices go out (spec section 7.2). Same rules as `NoticeTimes.kt` on Android.
public enum NoticeTimes {
  /// The guest warning comes 44 days after the app was last used, 15 days before the server
  /// forgets an inactive guest.
  public static let guestAfter: TimeInterval = 44 * 86_400

  /// The zone named [id], or [fallback] when there is none or the phone does not know it.
  public static func zone(_ id: String?, fallback: TimeZone) -> TimeZone {
    guard let id, !id.trimmingCharacters(in: .whitespaces).isEmpty else { return fallback }
    return TimeZone(identifier: id) ?? fallback
  }

  /// The next 9:00 in [zone] after [now]: today's when it is still ahead, else tomorrow's. The zone
  /// is the profile's (where "today" is read for the payments), never the phone's or UTC. Computed
  /// with a calendar in that zone, so a day with a clock change still lands on 9:00 local.
  public static func nextNine(after now: Date, in zone: TimeZone) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let nine = DateComponents(hour: 9, minute: 0, second: 0)
    // `nextDate(after:)` is exclusive, so at exactly 9:00 the next one is tomorrow's.
    return calendar.nextDate(after: now, matching: nine, matchingPolicy: .nextTime)
      ?? now.addingTimeInterval(86_400)
  }
}

/// The words of the due notice: names joined as "A", "A y B", "A, B y C". Same rules as
/// `NoticeText.kt` on Android.
public enum NoticeText {
  /// [names] trimmed, blanks and repeats dropped, then joined with [and], or [andI] before a name
  /// that starts with the sound i. Empty when there is nothing to join.
  public static func join(_ names: [String], and: String, andI: String) -> String {
    var seen = Set<String>()
    let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
    guard let last = clean.last else { return "" }
    if clean.count == 1 { return last }
    return clean.dropLast().joined(separator: ", ") + " " + (startsWithI(last) ? andI : and) + " "
      + last
  }

  /// Spanish says "e" instead of "y" before the sound i: Internet, Hipoteca, Ítaca; not before a
  /// glide, as in Hielo or Iatrogenia. (English, Italian and Portuguese have the same word for both,
  /// so this is harmless there.)
  public static func startsWithI(_ name: String) -> Bool {
    let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let word = Array(
      lowered.drop(while: { !($0.isLetter || $0.isNumber) }))
    let glide: Set<Character> = ["a", "e", "o", "u", "á", "é", "ó", "ú"]
    func startsWithGlideless(after count: Int) -> Bool {
      guard word.count > count else { return true }
      return !glide.contains(word[count])
    }
    if word.starts(with: ["h", "i"]) { return startsWithGlideless(after: 2) }
    if word.first == "í" { return true }
    if word.first == "i" { return startsWithGlideless(after: 1) }
    return false
  }
}
