import AVFoundation
import WambitoNative

/// One recording on the `wambito/voice/events` stream (spec §3): the microphone ([VoiceRecorder]),
/// the audio kept in memory ([PcmBuffer], 30 s at most, never on disk, sent or logged), live
/// decodes of the whole buffer so far ([LiveSchedule], [LiveText]) and, when it ends, one final
/// decode with a 3 s limit.
///
/// Threads: everything of the run's own (state, buffer, schedule) and every start and stop of the
/// recorder (the audio session and the engine) run on [queue], one serial queue for the whole
/// channel: the audio session is the process's, so an earlier run's end (`.ambient`, deactivate)
/// always completes before the next run's begin (`.record`, activate), and two taps are never live
/// at once. Decodes run on [decodeQueue], one serial queue for the whole channel, so the one
/// recognizer is never used twice at once, not even by a late final decode of an earlier run; the
/// model cache loads on a third queue, so `acquire` (which blocks) never waits on its own queue.
/// Events go through [send], which hops to the main thread and drops them once the run is no longer
/// the channel's.
///
/// Every way out ends the audio session through the recorder's [VoiceSession] (once): a start that
/// fails, `stop`, the 30 s cap, an interruption, losing the input, `releaseModels`, the app going
/// to the background, Dart cancelling. Only the first end counts: a second `stop`, or a `stop`
/// after an error, finds the run no longer recording and does nothing.
final class VoiceRun {
  /// The final decode's limit, from `refining` (Refine.kt's 3 s).
  static let finalLimit: TimeInterval = 3

  private enum State { case starting, recording, ended }

  private let key: String
  private let precisePath: String
  private let cache: ModelCache<PreciseRecognizer>
  private let decodeQueue: DispatchQueue
  private let send: ([String: Any]) -> Void
  private let queue: DispatchQueue
  private let recorder = VoiceRecorder()

  private var state = State.starting
  private var buffer = PcmBuffer()
  private var schedule = LiveSchedule()
  private var busy = false
  private var lastPartial = ""
  private var observers: [NSObjectProtocol] = []

  init(
    precisePath: String, language: String, cache: ModelCache<PreciseRecognizer>,
    queue: DispatchQueue, decodeQueue: DispatchQueue, send: @escaping ([String: Any]) -> Void
  ) {
    self.precisePath = precisePath
    self.key = ModelCache<PreciseRecognizer>.key(path: precisePath, language: language)
    self.cache = cache
    self.queue = queue
    self.decodeQueue = decodeQueue
    self.send = send
  }

  /// Checks the model folder and the permission, starts loading the model if it is not, opens the
  /// microphone and sends `ready`; or sends one `error` (`no_model`, `permission`,
  /// `mic_unavailable`).
  func start(micGranted: @escaping () -> Bool) {
    queue.async { [self] in
      var isFolder: ObjCBool = false
      guard FileManager.default.fileExists(atPath: precisePath, isDirectory: &isFolder),
        isFolder.boolValue
      else { return fail("no_model") }
      guard micGranted() else { return fail("permission") }
      // Loads while the person talks when warmUp did not already.
      cache.warm(key) { _ in }
      do {
        try recorder.start { [weak self] chunk in
          guard let self else { return }
          self.queue.async { self.take(chunk) }
        }
      } catch {
        return fail("mic_unavailable")
      }
      state = .recording
      observe()
      send(["type": "ready"])
    }
  }

  /// Ends the recording. With [refine] the final decode follows (`refining`, then `refined` or
  /// `refine_failed`); then `done`. Does nothing once the run has ended.
  func stop(refine: Bool) {
    queue.async { [self] in finish(refine: refine) }
  }

  private func fail(_ code: String) {
    state = .ended
    recorder.stop()
    send(["type": "error", "code": code])
  }

  /// One 40 ms chunk from the microphone, on [queue].
  private func take(_ chunk: [Float]) {
    guard state == .recording else { return }
    send(["type": "level", "value": AudioLevel.of(chunk[...])])
    if !buffer.append(chunk[...]) {
      // The 30 s cap: ends as `stop` would.
      return finish(refine: true)
    }
    let loaded = cache.loadedKey() == key
    guard schedule.shouldDecode(samples: buffer.samples.count, busy: busy || !loaded) else { return }
    busy = true
    let samples = buffer.samples
    decodeQueue.async { [self] in
      let text = cache.acquire(key)?.transcribe(samples) ?? ""
      queue.async { [self] in
        busy = false
        guard state == .recording else { return }
        let shown = LiveText.shown(text, final: false)
        if shown != lastPartial {
          lastPartial = shown
          send(["type": "partial", "text": shown])
        }
      }
    }
  }

  /// On [queue].
  private func finish(refine: Bool) {
    guard state == .recording else { return }
    state = .ended
    unobserve()
    recorder.stop()
    let samples = buffer.samples
    buffer = PcmBuffer()
    if !refine || samples.isEmpty {
      send(["type": "done"])
      return
    }
    send(["type": "refining"])
    // Whichever comes first answers: the decode or the limit. A decode still running at the limit
    // is left to finish (the recognizer cannot be interrupted) and its text is dropped.
    let once = AnswerOnce()
    let send = self.send
    decodeQueue.async { [cache, key] in
      let text = cache.acquire(key)?.transcribe(samples)
      once.run {
        if let text {
          send(["type": "refined", "text": text])
        } else {
          send(["type": "refine_failed", "code": "failed"])
        }
        send(["type": "done"])
      }
    }
    queue.asyncAfter(deadline: .now() + Self.finalLimit) {
      once.run {
        send(["type": "refine_failed", "code": "timeout"])
        send(["type": "done"])
      }
    }
  }

  /// An interruption (a call, Siri), a route change that leaves no input, or the engine stopping on
  /// a configuration change ends the recording as `stop` would.
  private func observe() {
    let center = NotificationCenter.default
    let end: (Notification) -> Void = { [weak self] _ in self?.stop(refine: true) }
    observers.append(
      center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) {
        note in
        let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        if raw.flatMap(AVAudioSession.InterruptionType.init) == .began { end(note) }
      })
    observers.append(
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) {
        note in
        let audio = AVAudioSession.sharedInstance()
        if !audio.isInputAvailable || audio.currentRoute.inputs.isEmpty { end(note) }
      })
    // The engine stops itself on a configuration change (another input plugged in); only then.
    observers.append(
      center.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: recorder.engineObject, queue: nil
      ) { [weak self] note in
        guard let self, !self.recorder.isRunning else { return }
        end(note)
      })
  }

  private func unobserve() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
  }
}
