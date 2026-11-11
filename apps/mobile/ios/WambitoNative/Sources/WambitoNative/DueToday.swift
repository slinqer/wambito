import Foundation

/// The server a background run asks, as the app keeps it in secure storage (`setting.server`).
/// Same cases as `ServerSetting` in SecureSession.kt on Android.
public enum ServerSetting: Equatable {
  /// Nothing chosen in Settings: the build's default server.
  case notChosen
  case chosen(String)
  /// Something is stored but cannot be read: the run must not guess (nor send the token).
  case unreadable
}

/// "Hoy vence…" (spec section 7.2): what the daily run reads from the server and decides, without
/// the network, the Keychain or the notification centre. Same rules as `DueWorker` and
/// `NoticeApi.dueToday` on Android (NoticeWorkers.kt, NoticeApi.kt).
public enum DueToday {
  /// What the notices need of `GET /v1/me`.
  public struct Profile: Equatable {
    /// The profile's IANA zone: where "today" is read.
    public let timezone: String?
    /// A guest: no email yet.
    public let anonymous: Bool

    public init(timezone: String?, anonymous: Bool) {
      self.timezone = timezone
      self.anonymous = anonymous
    }
  }

  /// One page of `GET /v1/transactions`: the recurring payments still pending today on it, and
  /// whether paging stops here.
  public struct Page {
    public let names: [(createdAt: String, name: String)]
    public let stop: Bool
    public let next: String?
  }

  /// A server's answer to one read.
  public enum Answer {
    case ok(Data)
    /// 401: the server no longer knows the session.
    case unauthorized
    /// Offline, a timeout, a cancelled request, any other status.
    case failed
  }

  public enum Outcome: Equatable {
    /// The names to post, in order.
    case due([String])
    case nothingDue
    /// Before 9:00 in the profile's zone: nothing is asked of the payments yet.
    case beforeNine
    /// The notice for today was already posted.
    case alreadyToday
    /// A 401: no more runs until the app schedules one again.
    case signedOut
    /// The network or the server failed: tomorrow's run tries again.
    case failed
  }

  /// What a run found, and whether the next day's run goes on the calendar.
  public struct Run: Equatable {
    public let outcome: Outcome
    /// The profile's zone when the server gave one the phone knows, else the one known.
    public let zone: TimeZone
    /// The day the run read as today (`yyyy-MM-dd`), when it got that far.
    public let today: String?

    public var keepGoing: Bool { outcome != .signedOut }
  }

  /// The API's largest page.
  public static let pageSize = 200
  /// Pages read before giving up (`MAX_PAGES` in NoticeApi.kt).
  public static let maxPages = 10

  public static func parseProfile(_ data: Data) -> Profile? {
    guard let doc = object(data), let anonymous = doc["isAnonymous"] as? Bool else { return nil }
    let zone = (doc["timezone"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    return Profile(timezone: zone, anonymous: anonymous)
  }

  /// The query of one page of the month's pending transactions.
  public static func query(month: String, cursor: String?) -> String {
    "status=pending&month=\(month)&limit=\(pageSize)" + (cursor.map { "&cursor=\($0)" } ?? "")
  }

  /// [data] as a page, keeping the items dated [today], pending and from a recurring rule. The list
  /// comes newest first: paging stops when there is no next cursor, no item, or the oldest item is
  /// before [today]. Nil when it cannot be read.
  public static func parsePage(_ data: Data, today: String) -> Page? {
    guard let doc = object(data), let items = doc["items"] as? [Any] else { return nil }
    var names: [(createdAt: String, name: String)] = []
    var oldest: String?
    for entry in items {
      guard let item = entry as? [String: Any], let date = item["date"] as? String else { return nil }
      oldest = date
      let recurrence = item["recurrenceId"] as? String ?? ""
      if date == today, item["status"] as? String == "pending", !recurrence.isEmpty {
        guard let name = item["name"] as? String else { return nil }
        names.append((createdAt: item["createdAt"] as? String ?? "", name: name))
      }
    }
    let next = doc["nextCursor"] as? String
    let stop = next == nil || (oldest.map { $0 < today } ?? true)
    return Page(names: names, stop: stop, next: next)
  }

  /// The names, oldest first (by `createdAt`, then name).
  public static func ordered(_ names: [(createdAt: String, name: String)]) -> [String] {
    names.sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }.map(\.name)
  }

  /// The notice's words: [one] or [many] (a format with one `%@`) around the names joined with
  /// [NoticeText.join]. Empty when there is no name.
  public static func text(_ names: [String], one: String, many: String, and: String, andI: String)
    -> String
  {
    var seen = Set<String>()
    let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
    if clean.isEmpty { return "" }
    let joined = NoticeText.join(clean, and: and, andI: andI)
    return String(format: clean.count == 1 ? one : many, joined)
  }

  /// The server to ask: the chosen one, else [fallback] (the build's default). Nil when the setting
  /// cannot be read: never another server than the person's.
  public static func server(_ setting: ServerSetting, fallback: String?) -> String? {
    switch setting {
    case .notChosen: return fallback.flatMap { $0.isEmpty ? nil : $0 }
    case .chosen(let url): return url
    case .unreadable: return nil
    }
  }

  /// `<server>/api<path>`, http or https only.
  public static func url(server: String, path: String) -> URL? {
    var base = server
    while base.hasSuffix("/") { base.removeLast() }
    guard let url = URL(string: base + "/api" + path),
      let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil
    else { return nil }
    return url
  }

  /// [date]'s day in [zone], `yyyy-MM-dd`.
  public static func day(_ date: Date, in zone: TimeZone) -> String {
    let parts = calendar(zone).dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// One run: the profile (its zone), then, from 9:00 there and once a day, the pages of the
  /// month's pending transactions. [known] is the zone kept from before, [lastDay] the day the
  /// notice was last posted, [get] one authenticated read of a path under `/api`.
  public static func run(
    now: Date, known: TimeZone, lastDay: String?, get: (String) async -> Answer
  ) async -> Run {
    let profile: Profile
    switch await get("/v1/me") {
    case .unauthorized: return Run(outcome: .signedOut, zone: known, today: nil)
    case .failed: return Run(outcome: .failed, zone: known, today: nil)
    case .ok(let data):
      guard let read = parseProfile(data) else {
        return Run(outcome: .failed, zone: known, today: nil)
      }
      profile = read
    }
    let zone = NoticeTimes.zone(profile.timezone, fallback: known)
    if calendar(zone).component(.hour, from: now) < 9 {
      return Run(outcome: .beforeNine, zone: zone, today: nil)
    }
    let today = day(now, in: zone)
    if lastDay == today { return Run(outcome: .alreadyToday, zone: zone, today: today) }
    let month = String(today.prefix(7))
    var due: [(createdAt: String, name: String)] = []
    var cursor: String?
    for _ in 0..<maxPages {
      switch await get("/v1/transactions?" + query(month: month, cursor: cursor)) {
      case .unauthorized: return Run(outcome: .signedOut, zone: zone, today: today)
      case .failed: return Run(outcome: .failed, zone: zone, today: today)
      case .ok(let data):
        guard let page = parsePage(data, today: today) else {
          return Run(outcome: .failed, zone: zone, today: today)
        }
        due += page.names
        if page.stop {
          let names = ordered(due)
          return Run(outcome: names.isEmpty ? .nothingDue : .due(names), zone: zone, today: today)
        }
        cursor = page.next
      }
    }
    return Run(outcome: .failed, zone: zone, today: today)
  }

  private static func object(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func calendar(_ zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }
}
