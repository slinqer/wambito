import Foundation

/// The payments waiting to be saved by the headless engine's `captureMain`, the iOS twin of Android's
/// `CaptureQueue.kt` (spec 2026-11-22-ios-wallet-capture-design.md, section 3.2). One JSON file,
/// `wambito.capture.queue.json` in Application Support, readable once the phone was unlocked after a
/// restart (a payment made with the phone locked must queue) and kept out of backups.
///
/// One difference with Android: an item queued with no session (a payment before any sign-in) is
/// given to the next account that adopts the queue instead of dropped.
public final class CaptureQueueStore {
  /// A capture a finished run left unsaved this many times is dropped.
  public static let maxRefusals = 8

  private struct State: Codable {
    var items: [Item] = []
    var owner: String?
    var confirms: [String] = []
    var refusals: [String: Int] = [:]
  }

  private struct Item: Codable {
    var key: String
    var kind: String
    var amount: Int64
    var currency: String
    var merchant: String
    var capturedAt: String
    var source: String
    var user: String?
  }

  private static let lock = NSLock()
  private let file: URL

  public init(file: URL) {
    self.file = file
  }

  /// The queue the app and its Shortcuts action share.
  public static func standard() -> CaptureQueueStore {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return CaptureQueueStore(file: support.appendingPathComponent("wambito.capture.queue.json"))
  }

  /// The account the queue belongs to now, if any.
  public var owner: String? { read().owner }

  /// Queues [payment] for the current owner; returns its key (the `Idempotency-Key` of its save).
  public func add(_ payment: WalletPayment, capturedAt: Date, source: String) -> String {
    let key = UUID().uuidString.lowercased()
    update { state in
      state.items.append(
        Item(
          key: key, kind: "expense", amount: payment.cents, currency: payment.currency,
          merchant: payment.merchant, capturedAt: Self.iso(capturedAt), source: source,
          user: state.owner))
    }
    return key
  }

  /// [userId]'s captures, oldest first, as `QueuedCapture.fromJson` reads them, and the confirms.
  /// Nothing is removed.
  public func take(userId: String) -> (captures: [[String: Any]], confirms: [String]) {
    let state = read()
    let captures = state.items.filter { $0.user == userId }.map { item -> [String: Any] in
      [
        "key": item.key, "kind": item.kind, "amount": Int(item.amount), "currency": item.currency,
        "merchant": item.merchant, "capturedAt": item.capturedAt, "source": item.source,
      ]
    }
    return (captures, state.owner == userId ? state.confirms : [])
  }

  public func isEmpty(userId: String) -> Bool {
    !read().items.contains { $0.user == userId }
  }

  /// [userId] signed in: its items stay, [from]'s and untagged ones become its, the rest go.
  public func adopt(userId: String, from: String?) {
    update { state in
      state.items = state.items.compactMap { item in
        var item = item
        if item.user == userId { return item }
        if item.user == nil || (from != nil && item.user == from) {
          item.user = userId
          return item
        }
        return nil
      }
      let keys = Set(state.items.map(\.key))
      state.refusals = state.refusals.filter { keys.contains($0.key) }
      if state.owner != userId && (from == nil || state.owner != from) { state.confirms = [] }
      state.owner = userId
    }
  }

  /// "Bien" on a notification: confirm [txId] at the next run.
  public func addConfirm(_ txId: String) {
    update { state in
      if !state.confirms.contains(txId) { state.confirms.append(txId) }
    }
  }

  /// The run saved these captures and applied these confirms.
  public func ack(keys: [String], confirms: [String]) {
    update { state in
      state.items.removeAll { keys.contains($0.key) }
      state.confirms.removeAll { confirms.contains($0) }
      for key in keys { state.refusals[key] = nil }
    }
  }

  /// A finished run left [keys] unsaved: counts one more refusal each; returns the keys dropped now.
  public func refuse(keys: [String], limit: Int) -> [String] {
    var dropped: [String] = []
    update { state in
      for key in keys where state.items.contains(where: { $0.key == key }) {
        let count = (state.refusals[key] ?? 0) + 1
        if count >= limit {
          state.items.removeAll { $0.key == key }
          state.refusals[key] = nil
          dropped.append(key)
        } else {
          state.refusals[key] = count
        }
      }
    }
    return dropped
  }

  /// Sign-out: everything goes.
  public func clear() {
    update { $0 = State() }
  }

  private func read() -> State {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return load()
  }

  private func update(_ change: (inout State) -> Void) {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var state = load()
    change(&state)
    save(state)
  }

  private func load() -> State {
    guard let data = try? Data(contentsOf: file) else { return State() }
    return (try? JSONDecoder().decode(State.self, from: data)) ?? State()
  }

  private func save(_ state: State) {
    let folder = file.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let data = try? JSONEncoder().encode(state) else { return }
    #if os(iOS)
      try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
      try? data.write(to: file, options: .atomic)
    #endif
    _ = BackupExclusion.exclude(path: file.path)
  }

  private static func iso(_ date: Date) -> String {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    format.timeZone = TimeZone(identifier: "UTC")
    return format.string(from: date)
  }
}
