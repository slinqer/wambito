import AVFoundation
import Flutter
import UIKit
import WambitoNative

/// Quick capture's ears on iOS (lib/capture/engine/voice_channel.dart), on the `wambito/voice`
/// method channel and the `wambito/voice/events` event channel, with the names, arguments, events
/// and error codes of Android's `VoiceChannel.kt` (spec §3). iOS runs only the precise model
/// (sherpa-onnx: Canary for es/en, Parakeet for it/pt, [PreciseRecognizer]); there is no Vosk, so
/// no `modelPath`, `grammar` or `result` events.
///
/// Methods: `supported` -> true; `requestPermission` -> Bool; `deviceQualifies({minRamBytes?})` ->
/// Bool (physical memory, 3 GiB by default); `warmUp({precisePath, language})` -> Bool (loads the
/// model in the background and keeps it; true once loaded); `isWarm({precisePath, language})` ->
/// Bool (loaded and the microphone granted); `stop`; `modelsDirectory` -> String (Application
/// Support/voice-models, excluded from backup); `freeBytes` -> Int; `unzip({zip, into})`;
/// `releaseModels` (ends a recording, frees the model).
/// Events, after listening with `{precisePath, language}` ([VoiceRun]): `{type: ready}`,
/// `{type: level, value}` (0..1, 25 a second), `{type: partial, text}`, then `{type: refining}` and
/// `{type: refined, text}` or `{type: refine_failed, code}` (`timeout`, `failed`), then
/// `{type: done}`; or `{type: error, code}` (`bad_arguments`, `no_model`, `permission`,
/// `mic_unavailable`). After `done` or `error` nothing more is sent, and the stream is not ended,
/// as on Android.
///
/// Every answer to Flutter and every event is sent on the main thread.
final class VoiceChannel: NSObject, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  /// Opens models (and waits for them in `warm`); never used for `acquire`, which blocks.
  private let loadQueue = DispatchQueue(label: "com.wambito.voice.load", qos: .userInitiated)
  /// Every run's state and every recorder start and stop, of every run, in order (VoiceRun).
  private let runQueue = DispatchQueue(label: "com.wambito.voice.run", qos: .userInitiated)
  /// Every decode, live or final, of every run: one recognizer, one decode at a time.
  private let decodeQueue = DispatchQueue(label: "com.wambito.voice.decode", qos: .userInitiated)
  private let files = DispatchQueue(label: "com.wambito.voice.files", qos: .utility)
  private let cache: ModelCache<PreciseRecognizer>

  // Main thread only.
  private var sink: FlutterEventSink?
  private var session = 0
  private var run: VoiceRun?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "wambito/voice", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "wambito/voice/events", binaryMessenger: messenger)
    cache = ModelCache(
      open: { key in
        let split = key.lastIndex(of: "#")!
        return try PreciseRecognizer(
          path: String(key[..<split]), language: String(key[key.index(after: split)...]))
      },
      queue: loadQueue)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      self.handle(call, result)
    }
    events.setStreamHandler(self)
    let center = NotificationCenter.default
    // Memory pressure forgets the model; a recording keeps the one it holds until it ends, so its
    // live text goes on and its final decode does not load the model again (VoiceRun).
    observers.append(
      center.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.cache.drop() })
    // In the background the microphone is let go at once, as Android's onStop.
    observers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.run?.stop(refine: false) })
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "supported":
      result(true)
    case "requestPermission":
      requestPermission(result)
    case "deviceQualifies":
      let minimum = (args?["minRamBytes"] as? NSNumber)?.uint64Value
      result(MemoryRule.qualifies(physical: ProcessInfo.processInfo.physicalMemory, minimum: minimum))
    case "warmUp":
      guard let key = Self.key(args) else {
        return result(FlutterError(code: "failed", message: "Missing precisePath or language", details: nil))
      }
      guard Self.qualifies() else { return result(false) }
      cache.warm(key) { loaded in DispatchQueue.main.async { result(loaded) } }
    case "isWarm":
      guard let key = Self.key(args) else { return result(false) }
      result(cache.loadedKey() == key && Self.micGranted())
    case "stop":
      run?.stop(refine: true)
      result(nil)
    case "modelsDirectory":
      do {
        result(try Self.modelsDirectory().path)
      } catch {
        result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
      }
    case "freeBytes":
      let folder = try? Self.modelsDirectory()
      let values = try? folder?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      result(values?.volumeAvailableCapacityForImportantUsage.map { NSNumber(value: $0) })
    case "unzip":
      guard let zip = args?["zip"] as? String, let into = args?["into"] as? String else {
        return result(FlutterError(code: "failed", message: "Missing zip or into", details: nil))
      }
      files.async {
        do {
          try ZipExtract.unzip(URL(fileURLWithPath: zip), into: URL(fileURLWithPath: into, isDirectory: true))
          DispatchQueue.main.async { result(nil) }
        } catch {
          let message = String(describing: error)
          DispatchQueue.main.async { result(FlutterError(code: "failed", message: message, details: nil)) }
        }
      }
    case "releaseModels":
      // A recording ends (done, without the final decode) and lets go of its model; a decode
      // running now keeps its own reference to it, which is freed after it.
      run?.stop(refine: false)
      cache.drop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Events

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    run?.stop(refine: false)
    session += 1
    let id = session
    sink = events
    let args = arguments as? [String: Any]
    guard let path = args?["precisePath"] as? String, let language = args?["language"] as? String else {
      run = nil
      events(["type": "error", "code": "bad_arguments"])
      return nil
    }
    let run = VoiceRun(
      precisePath: path, language: language, cache: cache, queue: runQueue, decodeQueue: decodeQueue,
      send: { [weak self] event in
        DispatchQueue.main.async {
          guard let self, self.session == id else { return }
          self.sink?(event)
        }
      })
    self.run = run
    run.start(micGranted: Self.micGranted)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    // Dart stopped listening (the sheet closed): stop recording, send nothing more.
    session += 1
    run?.stop(refine: false)
    run = nil
    sink = nil
    return nil
  }

  // MARK: Helpers

  /// The cache key from `precisePath` and `language`, when both are given.
  private static func key(_ args: [String: Any]?) -> String? {
    guard let path = args?["precisePath"] as? String, let language = args?["language"] as? String else {
      return nil
    }
    return ModelCache<PreciseRecognizer>.key(path: path, language: language)
  }

  /// This phone gets the precise model at all (3 GiB).
  private static func qualifies() -> Bool {
    MemoryRule.qualifies(physical: ProcessInfo.processInfo.physicalMemory, minimum: nil)
  }

  static func micGranted() -> Bool {
    if #available(iOS 17.0, *) {
      return AVAudioApplication.shared.recordPermission == .granted
    }
    return AVAudioSession.sharedInstance().recordPermission == .granted
  }

  private func requestPermission(_ result: @escaping FlutterResult) {
    let answer: (Bool) -> Void = { granted in DispatchQueue.main.async { result(granted) } }
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: answer)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(answer)
    }
  }

  /// Application Support/voice-models: created, and excluded from iCloud backup (the models are
  /// downloaded again when needed).
  private static func modelsDirectory() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var folder = support.appendingPathComponent("voice-models", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    return folder
  }
}
