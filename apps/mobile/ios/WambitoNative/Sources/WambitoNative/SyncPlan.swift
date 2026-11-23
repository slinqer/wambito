import Foundation

/// When the background sync (`wambito.sync`, a BGAppRefreshTask) is asked for and what counts as a
/// good run. The twin of `SyncScheduler.kt` / `SyncWorker.kt` on Android.
public enum SyncPlan {
  /// The system treats `earliestBeginDate` as a floor, not a time: 4 hours is the lightest ask that
  /// still keeps a vault fresh across a day.
  public static let interval: TimeInterval = 4 * 3_600

  /// The earliest the next run may begin, or nil when none should be waiting: only a `preview`
  /// account (its finances live in the vault) syncs in the background.
  public static func earliestBegin(mode: String?, now: Date) -> Date? {
    mode == "preview" ? now.addingTimeInterval(interval) : nil
  }

  /// Whether the run's outcome (`finished`'s `outcome`, or `timeout` / `expired` from native) is a
  /// good end for the task. `busy` is: another sync holds the vault and has the work in hand.
  public static func succeeded(_ outcome: String) -> Bool {
    outcome == "done" || outcome == "changed" || outcome == "busy"
  }

  /// Whether the task may go on to send the capture queue after the sync: never once it expired
  /// (the task is completed; an engine started then would be suspended holding the vault lease).
  public static func sendsCaptures(after outcome: String, mayStart: Bool) -> Bool {
    mayStart && outcome != "expired"
  }
}
