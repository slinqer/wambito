import Foundation

/// One step on the app's audio session, applied by the Runner's `VoiceRecorder` (AVAudioSession).
public enum SessionStep: Equatable {
  /// `.record` (mode `.measurement`) when true; `.ambient` when false.
  case category(record: Bool)
  /// `setActive(true)`.
  case activate
  /// `setActive(false, options: .notifyOthersOnDeactivation)`: music paused for the recording resumes.
  case deactivateNotifyingOthers
}

/// The audio session of one recording, with no AVFoundation: [begin] takes it for recording once,
/// [end] gives it back once, whichever way the recording ends (stop, error, interruption), so
/// another app's audio always resumes and never twice.
public struct VoiceSession {
  private var recording = false

  public init() {}

  /// The steps that take the session for recording; none when it is taken already.
  public mutating func begin() -> [SessionStep] {
    if recording { return [] }
    recording = true
    return [.category(record: true), .activate]
  }

  /// The steps that give the session back; none when it was not taken or was given back already.
  public mutating func end() -> [SessionStep] {
    if !recording { return [] }
    recording = false
    return [.category(record: false), .deactivateNotifyingOthers]
  }
}
