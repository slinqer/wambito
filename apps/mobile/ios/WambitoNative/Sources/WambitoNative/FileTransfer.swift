import Foundation

/// The parts of the files channel that need no UIKit: reading a file within a limit, and the names
/// and numbers the Dart side hands over. Same rules as the Android side (FileTransfer.kt).
public enum FileTransfer {
    /// The limit when the caller gives none (the import's, 5 MB).
    public static let defaultLimit = 5 * 1024 * 1024

    /// No limit asked for goes past this: a file is held in memory whole.
    public static let maxLimit = 32 * 1024 * 1024

    private static let maxName = 120
    private static let fallbackName = "wambito"

    /// A file name that is safe to put in the app's temporary folder: no folders (`../../x` stays
    /// `x`), no control characters, no leading dots, at most 120 characters with the extension
    /// kept. A name with nothing left is `wambito`.
    public static func safeName(_ name: String) -> String {
        let leaf = name.split(separator: "/", omittingEmptySubsequences: false).last
            .flatMap { $0.split(separator: "\\", omittingEmptySubsequences: false).last }
            .map(String.init) ?? ""
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: leaf.unicodeScalars.filter { $0.properties.generalCategory != .control })
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        let noDots = String(trimmed.drop(while: { $0 == "." }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if noDots.isEmpty { return fallbackName }
        if noDots.count <= maxName { return noDots }
        var ext = ""
        if let dot = noDots.lastIndex(of: "."), dot != noDots.startIndex {
            let tail = String(noDots[dot...])
            if tail.count <= 16 { ext = tail }
        }
        return String(noDots.prefix(maxName - ext.count)) + ext
    }

    /// The size limit a call asked for, within what is sane.
    public static func limitOf(_ argument: Any?) -> Int {
        guard let asked = (argument as? NSNumber)?.int64Value else { return defaultLimit }
        if asked <= 0 { return defaultLimit }
        if asked > Int64(maxLimit) { return maxLimit }
        return Int(asked)
    }

    /// Reads the file whole, or nil when it holds more than `limit` bytes (or cannot be read). It
    /// never reads more than one byte past `limit`.
    public static func readBounded(_ url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1) else { return nil }
        return data.count > limit ? nil : data
    }
}

/// One pick or save at a time: `begin` is true for the caller that got the slot, `end` frees it.
public final class Busy {
    private let lock = NSLock()
    private var active = false

    public init() {}

    public func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if active { return false }
        active = true
        return true
    }

    public func end() {
        lock.lock()
        active = false
        lock.unlock()
    }
}
