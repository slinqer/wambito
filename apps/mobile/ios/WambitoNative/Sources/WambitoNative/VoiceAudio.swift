import Foundation

/// The loudness of a chunk of microphone audio, for the level meter while recording.
public enum AudioLevel {
  /// Quietest level shown, in dBFS: at or below it the meter is empty.
  private static let floorDb = -50.0

  /// 0...1 from [samples] (each -1...1): RMS in dBFS, then (dB + 50) / 50 clamped. Empty or
  /// all-zero samples are 0.
  public static func of(_ samples: ArraySlice<Float>) -> Double {
    if samples.isEmpty { return 0 }
    var sum = 0.0
    for sample in samples { sum += Double(sample) * Double(sample) }
    let rms = (sum / Double(samples.count)).squareRoot()
    if rms <= 0 { return 0 }
    let db = 20 * log10(rms)
    return min(1, max(0, (db - floorDb) / -floorDb))
  }
}

/// The recording kept in memory as 16 kHz mono floats, capped at 30 seconds.
public struct PcmBuffer {
  public static let sampleRate = 16_000
  public static let maxSamples = 480_000

  public private(set) var samples: [Float] = []

  public init() {}

  /// Adds [chunk]; keeps exactly up to the cap and returns false when the cap cut it or was
  /// already reached.
  public mutating func append(_ chunk: ArraySlice<Float>) -> Bool {
    let room = PcmBuffer.maxSamples - samples.count
    if room <= 0 { return false }
    if chunk.count > room {
      samples.append(contentsOf: chunk.prefix(room))
      return false
    }
    samples.append(contentsOf: chunk)
    return true
  }
}
