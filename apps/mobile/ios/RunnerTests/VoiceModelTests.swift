import XCTest

@testable import Runner

/// The precise models on real speech (spec §3): each fixture is a sentence spoken by macOS `say`
/// (invented, 16 kHz mono 16-bit), and the model must hear its meal word.
///
/// Needs the unzipped `voice-models-v2` zips: run with `TEST_RUNNER_WAMBITO_VOICE_MODELS=<folder>`
/// (xcodebuild hands `TEST_RUNNER_*` to the test without the prefix). Each model is found as a
/// folder named after its zip (`sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8`,
/// `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`, the names in `models_download.dart`), directly in
/// that folder or one level below. Without the variable, or without the model, the test is skipped.
final class VoiceModelTests: XCTestCase {
  private static let canary = "sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8"
  private static let parakeet = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"

  func testCanaryTranscribesSpanish() throws {
    let text = try transcribe(model: Self.canary, language: "es", fixture: "voice-es")
    XCTAssertTrue(Self.words(text).contains("almuerzo"), "Canary heard: \(text)")
  }

  func testParakeetTranscribesPortuguese() throws {
    let text = try transcribe(model: Self.parakeet, language: "pt", fixture: "voice-pt")
    XCTAssertTrue(Self.words(text).contains("almoço"), "Parakeet heard: \(text)")
  }

  private func transcribe(model: String, language: String, fixture: String) throws -> String {
    guard let root = ProcessInfo.processInfo.environment["WAMBITO_VOICE_MODELS"], !root.isEmpty else {
      throw XCTSkip("WAMBITO_VOICE_MODELS is not set")
    }
    guard let folder = Self.find(model, in: URL(fileURLWithPath: root, isDirectory: true)) else {
      throw XCTSkip("\(model) is not in \(root)")
    }
    let url = try XCTUnwrap(
      Bundle(for: VoiceModelTests.self).url(forResource: fixture, withExtension: "wav"))
    let samples = try Self.samples(wav: Data(contentsOf: url))
    let recognizer = try PreciseRecognizer(path: folder.path, language: language)
    let start = Date()
    let text = recognizer.transcribe(samples)
    let seconds = Date().timeIntervalSince(start)
    // In the result bundle's activities: the transcript and the decode time (the final decode has
    // 3 s on the phone).
    XCTContext.runActivity(
      named: "\(model): \"\(text)\" decoded in \(String(format: "%.2f", seconds)) s"
    ) { _ in }
    return text
  }

  /// The folder named [name] in [root] or in one of its subfolders.
  private static func find(_ name: String, in root: URL) -> URL? {
    let fm = FileManager.default
    let direct = root.appendingPathComponent(name, isDirectory: true)
    if fm.fileExists(atPath: direct.path) { return direct }
    let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return children.map { $0.appendingPathComponent(name, isDirectory: true) }
      .first { fm.fileExists(atPath: $0.path) }
  }

  /// [text] lowercased with its punctuation turned to spaces ("Almuerzo." → "almuerzo").
  private static func words(_ text: String) -> [String] {
    text.lowercased()
      .components(separatedBy: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
      .filter { !$0.isEmpty }
  }

  /// The samples of a 16 kHz mono 16-bit little-endian PCM WAV, in -1...1. The RIFF chunks are
  /// walked to `data` (`say` writes `JUNK` and `FLLR` chunks before it, so the header is not 44
  /// bytes).
  static func samples(wav: Data) throws -> [Float] {
    let bytes = [UInt8](wav)
    func u32(_ at: Int) -> Int {
      Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
    }
    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    guard bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
      String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE"
    else { throw WavError.notWav }
    var offset = 12
    var format: (channels: Int, rate: Int, bits: Int)?
    while offset + 8 <= bytes.count {
      let id = String(bytes: bytes[offset..<offset + 4], encoding: .ascii)
      let size = u32(offset + 4)
      let body = offset + 8
      guard body + size <= bytes.count else { throw WavError.truncated }
      if id == "fmt " {
        guard size >= 16, u16(body) == 1 else { throw WavError.unsupported }
        format = (u16(body + 2), u32(body + 4), u16(body + 14))
      } else if id == "data" {
        guard let format, format.channels == 1, format.rate == 16_000, format.bits == 16 else {
          throw WavError.unsupported
        }
        return stride(from: body, to: body + size - 1, by: 2).map {
          Float(Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)) / 32768
        }
      }
      offset = body + size + (size & 1)
    }
    throw WavError.noData
  }

  enum WavError: Error {
    case notWav, truncated, unsupported, noData
  }
}
