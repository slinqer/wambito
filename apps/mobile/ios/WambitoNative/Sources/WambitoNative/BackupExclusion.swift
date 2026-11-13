import Foundation

/// Keeps the vault out of iCloud and device backups (the `excludeFromBackup` call of the
/// `wambito/device` channel). Set on the folder that holds the vault, it covers the SQLite side
/// files too.
public enum BackupExclusion {
    /// True when [path] now carries the exclusion; false when it does not exist or cannot be set.
    public static func exclude(path: String) -> Bool {
        var url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }
}
