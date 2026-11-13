import Foundation

/// Whether the signed-in account's finances live on the server (`plain`) or only in the vault on the
/// phone, end-to-end encrypted (`preview`), kept where a background run can read it. The app writes
/// it (`wambito/notices` `setEncryptionMode`) whenever it knows the mode and clears it on sign-out;
/// the twin of `account/AccountMode.kt` on Android.
///
/// Values: `plain`, `preview`, `unknown` (signed in, the app has not learned the mode yet) and
/// absent (nobody told: an install from before the vault, or signed out).
public enum AccountMode {
  /// The key the app and the background runs share, as on Android. Nothing secret.
  public static let key = "wambito.encryption.mode"

  public static func read(_ defaults: UserDefaults = .standard) -> String? {
    defaults.string(forKey: key)
  }

  public static func write(_ mode: String?, defaults: UserDefaults = .standard) {
    if let mode { defaults.set(mode, forKey: key) } else { defaults.removeObject(forKey: key) }
  }

  /// Only a `plain` account (or one from before the vault, which never wrote a mode) lets a
  /// background run touch the API. `preview` never does; `unknown` waits for the app to learn it.
  public static func allowsApi(_ mode: String?) -> Bool { mode == nil || mode == "plain" }

  /// What the daily "Hoy vence…" run does for [mode].
  public enum DueRun: Equatable {
    /// Asks the server as ever.
    case ask
    /// Asks nothing today; tomorrow's run looks again (the mode is not known yet).
    case skipToday
    /// Asks nothing and is not scheduled again: the account's payments live only on the phone.
    case stop
  }

  public static func dueRun(_ mode: String?) -> DueRun {
    if allowsApi(mode) { return .ask }
    return mode == "preview" ? .stop : .skipToday
  }
}
