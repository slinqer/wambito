import XCTest
@testable import WambitoNative

final class FileTransferTests: XCTestCase {
    func testSafeNameDropsFolders() {
        XCTAssertEqual(FileTransfer.safeName("../../etc/passwd"), "passwd")
        XCTAssertEqual(FileTransfer.safeName("C:\\x\\y.csv"), "y.csv")
    }

    func testSafeNameFallsBack() {
        XCTAssertEqual(FileTransfer.safeName("..."), "wambito")
        XCTAssertEqual(FileTransfer.safeName("  "), "wambito")
    }

    func testSafeNameDropsControlCharacters() {
        XCTAssertEqual(FileTransfer.safeName("a\u{0007}b.csv"), "ab.csv")
    }

    func testSafeNameShortensKeepingExtension() {
        let name = FileTransfer.safeName(String(repeating: "a", count: 200) + ".csv")
        XCTAssertEqual(name.count, 120)
        XCTAssertTrue(name.hasSuffix(".csv"))
    }

    func testLimitOf() {
        XCTAssertEqual(FileTransfer.limitOf(nil), FileTransfer.defaultLimit)
        XCTAssertEqual(FileTransfer.limitOf(0), FileTransfer.defaultLimit)
        XCTAssertEqual(FileTransfer.limitOf(-1), FileTransfer.defaultLimit)
        XCTAssertEqual(FileTransfer.limitOf(1_000_000_000), FileTransfer.maxLimit)
        XCTAssertEqual(FileTransfer.limitOf(1000), 1000)
        XCTAssertEqual(FileTransfer.limitOf("x"), FileTransfer.defaultLimit)
    }

    func testReadBoundedRespectsLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data(0..<10)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(FileTransfer.readBounded(url, limit: 9))
        XCTAssertEqual(FileTransfer.readBounded(url, limit: 10), bytes)
    }

    func testReadBoundedMissingFileIsNil() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNil(FileTransfer.readBounded(url, limit: 10))
    }

    func testSecondPickIsBusy() {
        let busy = Busy()
        XCTAssertTrue(busy.begin())
        XCTAssertFalse(busy.begin())
        busy.end()
        XCTAssertTrue(busy.begin())
    }
}
