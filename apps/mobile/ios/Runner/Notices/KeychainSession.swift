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

  /// The token's item: missing (signed out), unreadable (locked) or its value.
  func token() -> StoredItem { read(Self.tokenKey) }

  func server() -> ServerSetting { ServerSetting.of(read(Self.serverKey)) }

  private func read(_ account: String) -> StoredItem {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    return StoredItem.of(status: status, data: found as? Data)
  }
}
