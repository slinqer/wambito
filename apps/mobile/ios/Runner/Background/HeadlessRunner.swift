import Flutter
import Foundation

/// One Dart entry point (`syncMain`) in a headless Flutter engine, the iOS side of
/// `HeadlessRunner.kt`. The engine ends exactly once, on whichever comes first: Dart's `finished`,
/// the [budget], or [abort] (the task's `expirationHandler`); [run]'s completion is called once, on
/// the main thread, with the outcome: `finished`'s, or `timeout`, `expired`, `busy` (a run is
/// already going) or `failed` (the engine did not start).
///
/// Everything touching the engine happens on the main thread. Nothing here sends anything: the
/// outcome is only a word.
final class HeadlessRunner {
  /// The run in progress, if any (main thread only).
  private static var current: HeadlessRunner?

  private var engine: FlutterEngine?
  private var background: BackgroundChannel?
  private var notices: NoticesChannel?
  private var timer: DispatchWorkItem?
  private var completion: ((String) -> Void)?

  private init() {}

  /// Starts the run; callable from any thread.
  static func run(
    entrypoint: String, budget: TimeInterval = 25, completion: @escaping (String) -> Void
  ) {
    onMain {
      guard current == nil else {
        completion("busy")
        return
      }
      let runner = HeadlessRunner()
      current = runner
      runner.start(entrypoint: entrypoint, budget: budget, completion: completion)
    }
  }

  /// Now when already on the main thread (so a start asked for before an [abort] comes before it),
  /// else on the main queue.
  private static func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
  }

  /// Ends the run in progress, if any, as `expired`; callable from any thread.
  static func abort() {
    onMain { current?.finish("expired") }
  }

  private func start(
    entrypoint: String, budget: TimeInterval, completion: @escaping (String) -> Void
  ) {
    self.completion = completion
    let engine = FlutterEngine(name: "wambito.background", project: nil, allowHeadlessExecution: true)
    self.engine = engine
    guard engine.run(withEntrypoint: entrypoint) else {
      finish("failed")
      return
    }
    GeneratedPluginRegistrant.register(with: engine)
    let messenger = engine.binaryMessenger
    background = BackgroundChannel(messenger: messenger) { [weak self] outcome in
      // Not inside the engine's own `finished` handler: destroying the engine there would tear it
      // down under the call that is still answering. The next turn of the main queue ends it.
      DispatchQueue.main.async { self?.finish(outcome) }
    }
    notices = NoticesChannel(messenger: messenger)
    let item = DispatchWorkItem { [weak self] in self?.finish("timeout") }
    timer = item
    DispatchQueue.main.asyncAfter(deadline: .now() + budget, execute: item)
  }

  /// The one end: later calls (a `finished` after the budget, say) do nothing.
  private func finish(_ outcome: String) {
    guard let completion else { return }
    self.completion = nil
    timer?.cancel()
    timer = nil
    background?.close()
    background = nil
    notices = nil
    engine?.destroyContext()
    engine = nil
    if HeadlessRunner.current === self { HeadlessRunner.current = nil }
    completion(outcome)
  }
}
