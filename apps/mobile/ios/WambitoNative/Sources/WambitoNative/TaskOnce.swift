import Foundation

/// The end of one background task, which the system may expire at any moment (`SyncTask.swift`):
/// it ends once ([end]), and an engine never starts once it was aborted or ended ([mayStart]), so
/// nothing runs after `setTaskCompleted`. Used on the main thread only.
public final class TaskOnce {
  private var aborted = false
  private var ended = false

  public init() {}

  /// Whether the run may still start its engine.
  public var mayStart: Bool { !aborted && !ended }

  /// True the first time only: the caller then completes the task.
  public func end() -> Bool {
    guard !ended else { return false }
    ended = true
    return true
  }

  /// The system's expiration: no engine starts from now on. True when the task is still to be
  /// completed ([end]).
  public func abort() -> Bool {
    aborted = true
    return end()
  }
}
