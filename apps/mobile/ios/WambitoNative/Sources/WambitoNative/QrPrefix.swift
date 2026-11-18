import Foundation

/// Which QRs a `wambito/scanner` `scan` takes (Runner/Scanner), as `ScannerPrefix.kt` on Android:
/// the pairing link (lib/local/pairing.dart) unless the call asks for the web sign-in's
/// (lib/local/signin_approval.dart). Only these two are ever known; any other prefix Dart may send
/// is dropped, and nothing asked is the pairing one, never "anything".
public enum QrPrefix {
    public static let pair = "wambito://pair?"
    public static let signin = "wambito://signin?"
    public static let known = [pair, signin]

    /// The prefixes a `scan` call's `prefixes` argument asks for, kept to [known].
    public static func of(_ argument: Any?) -> [String] {
        var asked: [String] = []
        for case let prefix as String in (argument as? [Any]) ?? [] where known.contains(prefix) {
            if !asked.contains(prefix) { asked.append(prefix) }
        }
        return asked.isEmpty ? [pair] : asked
    }

    /// Whether a read QR's [text] is one the scan was asked for: one of [prefixes] the app knows.
    public static func accepts(_ text: String, prefixes: [String]) -> Bool {
        prefixes.contains { known.contains($0) && text.hasPrefix($0) }
    }
}
