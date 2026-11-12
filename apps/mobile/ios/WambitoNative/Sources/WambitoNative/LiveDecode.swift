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
}

/// Which phones may run the on-device voice model.
public enum MemoryRule {
  /// 3 GiB of physical memory.
  public static let defaultMinimum: UInt64 = 3 << 30

  public static func qualifies(physical: UInt64, minimum: UInt64?) -> Bool {
    physical >= (minimum ?? defaultMinimum)
  }
}
