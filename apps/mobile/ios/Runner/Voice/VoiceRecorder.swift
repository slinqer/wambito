import AVFoundation
import WambitoNative

/// Why the microphone could not start.
enum RecorderError: Error {
  /// The audio session refused `.record`, the input has no format (no microphone), the converter
  /// could not be made, or the engine did not start.
  case unavailable
}

/// The microphone for one recording (spec §3): the audio session taken for `.record` (mode
/// `.measurement`) while it runs and given back as `.ambient`, deactivated with
/// `.notifyOthersOnDeactivation` so other apps' audio resumes ([VoiceSession] decides the steps, so
/// it happens once whichever way the recording ends). `AVAudioEngine`'s input tap is converted with
/// `AVAudioConverter` to 16 kHz mono Float32 and handed on in 40 ms chunks (640 samples).
///
/// [start] and [stop] are called on the run's queue; [onChunk] is called on the audio thread.
final class VoiceRecorder {
  static let chunkSamples = 640

  private let engine = AVAudioEngine()
  private var session = VoiceSession()
  private var tapped = false
  /// Samples converted but not yet a whole chunk; touched only on the audio thread.
  private var carry: [Float] = []

  /// Takes the audio session, opens the microphone and calls [onChunk] with every 640 samples.
  /// On failure everything taken is given back before it throws.
  func start(onChunk: @escaping ([Float]) -> Void) throws {
    do {
      try apply(session.begin())
      let input = engine.inputNode
      let inFormat = input.outputFormat(forBus: 0)
      guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
        let outFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32, sampleRate: Double(PcmBuffer.sampleRate), channels: 1,
          interleaved: false),
        let converter = AVAudioConverter(from: inFormat, to: outFormat)
      else { throw RecorderError.unavailable }
      carry = []
      input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
        guard let self else { return }
        let samples = Self.convert(buffer, with: converter, to: outFormat)
        if samples.isEmpty { return }
        self.carry.append(contentsOf: samples)
        while self.carry.count >= Self.chunkSamples {
          let chunk = Array(self.carry.prefix(Self.chunkSamples))
          self.carry.removeFirst(Self.chunkSamples)
          onChunk(chunk)
        }
      }
      tapped = true
      engine.prepare()
      try engine.start()
    } catch {
      stop()
      throw RecorderError.unavailable
    }
  }

  /// The engine, to tell its configuration-change notices from others'.
  var engineObject: AnyObject { engine }

  /// False once the engine stopped, by [stop] or by itself (a configuration change).
  var isRunning: Bool { engine.isRunning }

  /// Closes the microphone and gives the audio session back. Safe to call more than once.
  func stop() {
    if tapped {
      engine.inputNode.removeTap(onBus: 0)
      tapped = false
    }
    if engine.isRunning { engine.stop() }
    try? apply(session.end())
  }

  private func apply(_ steps: [SessionStep]) throws {
    let audio = AVAudioSession.sharedInstance()
    for step in steps {
      switch step {
      case .category(record: true): try audio.setCategory(.record, mode: .measurement, options: [])
      case .category(record: false): try audio.setCategory(.ambient, mode: .default, options: [])
      case .activate: try audio.setActive(true)
      case .deactivateNotifyingOthers: try audio.setActive(false, options: .notifyOthersOnDeactivation)
      }
    }
  }

  /// [buffer] (the microphone's own format) as 16 kHz mono floats; empty when the conversion fails.
  private static func convert(
    _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
  ) -> [Float] {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return [] }
    var given = false
    var error: NSError?
    let status = converter.convert(to: out, error: &error) { _, inputStatus in
      if given {
        inputStatus.pointee = .noDataNow
        return nil
      }
      given = true
      inputStatus.pointee = .haveData
      return buffer
    }
    guard status != .error, error == nil, let data = out.floatChannelData else { return [] }
    return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
  }
}
