import Foundation

/// What the app asks the phone to open for it (the `openUrl` call of the `wambito/device` channel):
/// a web page (`http`, `https`) or an email to write (`mailto`). Nothing else: a `javascript:`, `file:`,
/// `tel:`, `sms:` or custom-scheme address is refused, whoever sent it.
public enum ExternalLinks {
    /// The address's scheme in lower case, or nil when it has none that is well formed.
    public static func schemeOf(_ address: String) -> String? {
        guard let colon = address.firstIndex(of: ":"), colon != address.startIndex else { return nil }
        let scheme = address[address.startIndex..<colon]
        // A leading space or control character is not a scheme: it is refused whole.
        guard let first = scheme.first, isAsciiLetter(first),
              scheme.allSatisfy({ isAsciiLetter($0) || isAsciiDigit($0) || "+-.".contains($0) })
        else { return nil }
        return scheme.lowercased()
    }

    /// True only for the kinds of address the app opens: `http`, `https` and `mailto`.
    public static func isOpenable(_ address: String?) -> Bool {
        guard let address, let scheme = schemeOf(address) else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private static func isAsciiLetter(_ c: Character) -> Bool {
        ("a"..."z").contains(c) || ("A"..."Z").contains(c)
    }

    private static func isAsciiDigit(_ c: Character) -> Bool {
        ("0"..."9").contains(c)
    }
}
