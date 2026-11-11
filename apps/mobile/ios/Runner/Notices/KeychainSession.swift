import Foundation
import Security
import WambitoNative

/// The session the app keeps in the Keychain with `flutter_secure_storage` (lib/api/session.dart,
/// lib/settings/settings_store.dart), as the background run reads it. Like `SecureStorageSession`
/// on Android it only reads: never a second copy of the token, never a write, so a background run
/// can never cost the person their session.
///
/// flutter_secure_storage_darwin 0.4.3 keeps each key as a generic password: service
/// `flutter_secure_storage_service` (`AppleOptions.defaultAccountName`), account = the key. The app
/// writes them readable after the first unlock (lib/storage/secure_storage.dart), so a locked phone
/// still answers.
struct KeychainSession {
  static let service = "flutter_secure_storage_service"
  /// lib/api/session.dart's `SessionStore.tokenKey`.
  static let tokenKey = "session.token"
  /// lib/settings/settings_store.dart's `serverUrlKey`.
  static let serverKey = "setting.server"

  /// The server of this build when the person chose none: `WambitoDefaultServer` in Info.plist, the
  /// value Android's `R.string.default_server` holds.
  static var defaultServer: String? {
    Bundle.main.object(forInfoDictionaryKey: "WambitoDefaultServer") as? String
  }

  private enum Item {
    case missing
    case unreadable
    case value(String)
  }

  /// The bearer token, or nil when signed out (or unreadable).
  func token() -> String? {
    if case .value(let token) = read(Self.tokenKey), !token.isEmpty { return token }
    return nil
  }

  func server() -> ServerSetting {
    switch read(Self.serverKey) {
    case .missing: return .notChosen
    case .unreadable: return .unreadable
    case .value(let url): return url.isEmpty ? .unreadable : .chosen(url)
    }
  }

  private func read(_ account: String) -> Item {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    if status == errSecItemNotFound { return .missing }
    // errSecInteractionNotAllowed (locked before the first unlock) and any other error: stored,
    // but not readable now.
    guard status == errSecSuccess, let data = found as? Data,
      let text = String(data: data, encoding: .utf8)
    else { return .unreadable }
    return .value(text)
  }
}
