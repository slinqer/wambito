import Foundation
import WambitoNative

/// Saves what the capture queue holds: `captureMain` in a headless engine (HeadlessRunner), which
/// writes each payment into the vault through the local backend and syncs (spec 2026-11-22, 3.2).
/// Swift never writes the vault. Only a finished run (`done`/`changed`) counts refusals; any other
/// outcome keeps the queue for the next run (the next payment, the app's start, `wambito.sync`).
enum CaptureRun {
  /// Posts or removes the "¿bien?" notifications for a run's answers (CaptureNotices, set at launch).
  static var announce: ([CaptureAnswer]) -> Void = { _ in }

  /// The runs waiting for the one in progress, if any (main thread only).
  private static var waiting: [(String) -> Void] = []
  private static var running = false

  /// "Probar": what a payment's notification looks like, with nothing queued or saved (set at
  /// launch with [announce]).
  static var test: () -> Void = {}

  /// Runs `captureMain` when the queue has something for its owner; [completion] gets the outcome
  /// (`empty` when there was nothing to save), on the main thread. A call made while a run is going
  /// waits for it and then runs again, so a payment queued meanwhile is never left behind.
  static func send(
    store: CaptureQueueStore = .standard(), budget: TimeInterval = 20,
    completion: ((String) -> Void)? = nil
  ) {
    DispatchQueue.main.async {
      if running {
        waiting.append { _ in send(store: store, budget: budget, completion: completion) }
        return
      }
      guard let owner = store.owner, !store.isEmpty(userId: owner) || !store.take(userId: owner).confirms.isEmpty
      else {
        completion?("empty")
        return
      }
      running = true
      HeadlessRunner.run(entrypoint: "captureMain", budget: budget) { outcome, captured in
        if outcome == "done" || outcome == "changed" {
          let left = store.take(userId: owner).captures.compactMap { $0["key"] as? String }
          _ = store.refuse(keys: left, limit: CaptureQueueStore.maxRefusals)
        }
        let answers = captured.compactMap(CaptureAnswer.parse)
        if answers.contains(where: { !$0.merged }) { CaptureSettings.markConfigured() }
        announce(answers)
        if outcome == "changed" { BackgroundChannel.app?.vaultChanged() }
        running = false
        completion?(outcome)
        let next = waiting
        waiting = []
        next.forEach { $0(outcome) }
      }
    }
  }
}
