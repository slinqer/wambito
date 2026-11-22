import XCTest
@testable import WambitoNative

final class BackupExclusionTests: XCTestCase {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wambito-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func isExcluded(_ url: URL) throws -> Bool {
        // A fresh URL: a URL caches the values it has read.
        try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
    }

    func testMarksAFolderExcluded() throws {
        let dir = try makeDir()
        XCTAssertFalse(try isExcluded(dir))
        XCTAssertTrue(BackupExclusion.exclude(path: dir.path))
        XCTAssertTrue(try isExcluded(dir))
    }

    func testMarksAFileExcluded() throws {
        let file = try makeDir().appendingPathComponent("wambito-vault-u.db")
        try Data("x".utf8).write(to: file)
        XCTAssertTrue(BackupExclusion.exclude(path: file.path))
        XCTAssertTrue(try isExcluded(file))
    }

    func testAMissingPathIsFalse() throws {
        let missing = try makeDir().appendingPathComponent("nope").path
        XCTAssertFalse(BackupExclusion.exclude(path: missing))
    }
}
