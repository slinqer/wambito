import BackgroundTasks
import Foundation
import WambitoNative

/// The vault's background sync (spec 7.1) as a background app refresh task, the iOS side of
/// `SyncWorker.kt`: the system wakes the app, a headless Flutter engine runs `syncMain`, and the
/// task ends with `setTaskCompleted` once, however the run ended (`finished`, the 25 s budget or the
/// system's `expirationHandler`). Only a `preview` account schedules it; a `plain` account has none
/// waiting, as before.
///
/// Native code sends nothing here: the engine's Dart syncs the sealed vault, or reports `locked`,
/// `signedOut` and so on, and then nothing is sent at all.
enum SyncTask {
  static let identifier = "wambito.sync"

  /// From `didFinishLaunching`, before the launch ends, as BGTaskScheduler requires.
  static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      handle(refresh)
    }
  }

  /// Puts the next run on the calendar in place of the one waiting: for a `preview` account only;
  /// any other mode that is not `unknown` takes the waiting request away.
  static func schedule(now: Date = Date(), defaults: UserDefaults = .standard) {
    let mode = AccountMode.read(defaults)
    guard let begin = SyncPlan.earliestBegin(mode: mode, now: now) else {
      if mode != "unknown" { cancel() }
      return
    }
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = begin
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      // Background refresh is off for the app, or too many requests: nothing to tell anyone.
      NSLog("Wambito: the sync could not be scheduled: \(error.localizedDescription)")
    }
  }

  static func cancel() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
  }

  private static func handle(_ task: BGAppRefreshTask) {
    // First, whatever follows: the next run is on the calendar even if this one dies.
    schedule()
    // Ends the task once, on the main thread (the system may call the expiration at any time,
    // even before the start below has run: `once` then keeps the engine from ever starting).
    let once = TaskOnce()
    let end: (Bool) -> Void = { success in
      if once.end() { task.setTaskCompleted(success: success) }
    }
    task.expirationHandler = {
      // Ends the engine if one runs (its completion then completes the task), and keeps one that
      // has not started yet from starting after `setTaskCompleted`.
      DispatchQueue.main.async {
        HeadlessRunner.abort()
        if once.abort() { task.setTaskCompleted(success: false) }
      }
    }
    DispatchQueue.main.async {
      guard once.mayStart else { return }
      // A `plain` account (or none) has nothing to sync: no engine, and nothing left waiting.
      guard AccountMode.read() == "preview" else {
        end(true)
        return
      }
      HeadlessRunner.run(entrypoint: "syncMain") { outcome in
        if outcome == "changed" { BackgroundChannel.app?.vaultChanged() }
        end(SyncPlan.succeeded(outcome))
      }
    }
  }
}
