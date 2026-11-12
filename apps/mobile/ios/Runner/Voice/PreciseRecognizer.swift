import Foundation
import WambitoNative

/// Why a precise model could not be opened.
enum PreciseModelError: Error {
  /// A file the model needs is not in its folder (named).
  case missingFile(String)
  /// sherpa-onnx refused the files.
  case notCreated
}

/// The precise voice model, run by sherpa-onnx (spec §3): NVIDIA Parakeet TDT 0.6B v3 when the
/// folder has a joiner (Italian, Portuguese; it finds the language itself), NVIDIA Canary otherwise
/// (Spanish, English; source and target language fixed when opened, punctuation on). The same files
/// and settings as Android's `CanaryRecognizer.kt` and `ParakeetRecognizer.kt`, with 2 threads.
///
/// Kept by `VoiceChannel`'s `ModelCache`, keyed `path#language`. Not thread-safe: one
/// [transcribe] at a time, which the channel's single decode queue guarantees. The C API is called
/// directly (not `SherpaOnnxOfflineRecognizer`, whose init stops the app when the files are bad), so
/// a broken model is an error, not a crash.
final class PreciseRecognizer {
  static let threads = 2
  private static let encoder = "encoder.int8.onnx"
  private static let decoder = "decoder.int8.onnx"
  private static let joiner = "joiner.int8.onnx"
  private static let tokens = "tokens.txt"

  private let recognizer: OpaquePointer

  /// Opens the model in the folder [path] for [language] (`es`, `en`, `it`, `pt`). Blocks for about
  /// a second or more: call it on the cache's load queue.
  init(path: String, language: String) throws {
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    let parakeet = PreciseRecognizer.isParakeet(folder)
    let needed = [Self.encoder, Self.decoder, Self.tokens] + (parakeet ? [Self.joiner] : [])
    for name in needed where !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
      throw PreciseModelError.missingFile(name)
    }
    let file = { (name: String) in folder.appendingPathComponent(name).path }
    // The config's strings are pointers into autoreleased NSStrings: they must outlive the create.
    let created: OpaquePointer? = autoreleasepool {
      let model: SherpaOnnxOfflineModelConfig
      if parakeet {
        model = sherpaOnnxOfflineModelConfig(
          tokens: file(Self.tokens),
          transducer: sherpaOnnxOfflineTransducerModelConfig(
            encoder: file(Self.encoder), decoder: file(Self.decoder), joiner: file(Self.joiner)),
          numThreads: Self.threads,
          provider: "cpu",
          debug: 0,
          modelType: "nemo_transducer")
      } else {
        model = sherpaOnnxOfflineModelConfig(
          tokens: file(Self.tokens),
          numThreads: Self.threads,
          provider: "cpu",
          debug: 0,
          canary: sherpaOnnxOfflineCanaryModelConfig(
            encoder: file(Self.encoder), decoder: file(Self.decoder),
            srcLang: language, tgtLang: language, usePnc: true))
      }
      var config = sherpaOnnxOfflineRecognizerConfig(
        featConfig: sherpaOnnxFeatureConfig(sampleRate: PcmBuffer.sampleRate, featureDim: 80),
        modelConfig: model)
      return SherpaOnnxCreateOfflineRecognizer(&config)
    }
    guard let created else { throw PreciseModelError.notCreated }
    recognizer = created
  }

  deinit {
    SherpaOnnxDestroyOfflineRecognizer(recognizer)
  }

  /// Parakeet (a transducer) is the only one with a joiner; Canary has an encoder and a decoder.
  static func isParakeet(_ folder: URL) -> Bool {
    FileManager.default.fileExists(atPath: folder.appendingPathComponent(joiner).path)
  }

  /// The text said in [samples] (16 kHz mono, -1...1), trimmed, with punctuation. Empty when
  /// sherpa-onnx gives nothing.
  func transcribe(_ samples: [Float]) -> String {
    guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
    defer { SherpaOnnxDestroyOfflineStream(stream) }
    SherpaOnnxAcceptWaveformOffline(stream, Int32(PcmBuffer.sampleRate), samples, Int32(samples.count))
    SherpaOnnxDecodeOfflineStream(recognizer, stream)
    guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
    defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
    guard let text = result.pointee.text else { return "" }
    return String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
