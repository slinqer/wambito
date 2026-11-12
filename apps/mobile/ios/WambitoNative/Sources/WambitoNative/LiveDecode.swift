import Foundation

/// When to decode the audio so far while recording: first at one second, then every half second,
/// never while a decode is still running.
public struct LiveSchedule {
  private let every: Int
  private var next: Int

  public init(first: Int = 16_000, every: Int = 8_000) {
    self.next = first
    self.every = every
  }

  /// True when [samples] reached the next point and no decode is [busy]. While busy the point
  /// stays, so the decode runs on the first chunk after it frees.
  public mutating func shouldDecode(samples: Int, busy: Bool) -> Bool {
    if busy || samples < next { return false }
    next = samples + every
    return true
  }
}

/// The text shown while recording.
public enum LiveText {
  /// [text] trimmed; until [final], without its last word, which may still be half said.
  public static func shown(_ text: String, final: Bool) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if final { return trimmed }
    guard let cut = trimmed.lastIndex(where: { $0.isWhitespace }) else { return "" }
    return String(trimmed[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// What to send as a last partial when the final decode fails or times out: the last live
  /// decode's whole text, last word included ([lastRaw]), so the text that stands is not one word
  /// short ("almuerzo 18 mil", not "almuerzo 18"). Nil when it is blank or was already sent
  /// ([lastPartial]).
  public static func fallback(lastRaw: String, lastPartial: String) -> String? {
    let full = shown(lastRaw, final: true)
    return full.isEmpty || full == lastPartial ? nil : full
  }
}

/// Which phones may run the on-device voice model.
public enum MemoryRule {
  /// 3 GiB of physical memory.
  public static let defaultMinimum: UInt64 = 3 << 30

  /// [minimum] can raise the floor, never lower it (Kotlin's `max(minRam, MIN_RAM)`).
  public static func qualifies(physical: UInt64, minimum: UInt64?) -> Bool {
    physical >= max(minimum ?? 0, defaultMinimum)
  }
}
