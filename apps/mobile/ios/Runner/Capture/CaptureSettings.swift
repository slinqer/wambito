import Foundation

/// The iPhone's capture switch and whether a payment ever arrived (spec 2026-11-22, sections 3.2 and
/// 3.4), in UserDefaults. Persistent names: `wambito.capture.sources`, `wambito.capture.configured`.
enum CaptureSettings {
  static let sourcesKey = "wambito.capture.sources"
  static let configuredKey = "wambito.capture.configured"
  static let wallet = "apple_wallet"

  /// Whether the Shortcuts action keeps payments. Never set counts as on: a person who installed the
  /// shortcut without opening the switch still gets their payments.
  static func walletOn(_ defaults: UserDefaults = .standard) -> Bool {
    guard let sources = defaults.stringArray(forKey: sourcesKey) else { return true }
    return sources.contains(wallet)
  }

  /// Turning it off also forgets that it was configured.
  static func setWallet(_ on: Bool, _ defaults: UserDefaults = .standard) {
    defaults.set(on ? [wallet] : [], forKey: sourcesKey)
    if !on { defaults.removeObject(forKey: configuredKey) }
  }

  static func configured(_ defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: configuredKey)
  }

  static func markConfigured(_ defaults: UserDefaults = .standard) {
    defaults.set(true, forKey: configuredKey)
  }
}
