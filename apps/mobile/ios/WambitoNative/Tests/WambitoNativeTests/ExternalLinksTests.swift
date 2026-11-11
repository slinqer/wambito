import XCTest
@testable import WambitoNative

final class ExternalLinksTests: XCTestCase {
    func testSchemeIsLowercased() {
        XCTAssertEqual(ExternalLinks.schemeOf("HTTPS://x"), "https")
    }

    func testMalformedSchemeIsNil() {
        XCTAssertNil(ExternalLinks.schemeOf("1http://x"))
        XCTAssertNil(ExternalLinks.schemeOf(":x"))
        XCTAssertNil(ExternalLinks.schemeOf(" http://x"))
        XCTAssertNil(ExternalLinks.schemeOf("no scheme"))
    }

    func testOnlyWebAndMailAreOpenable() {
        XCTAssertTrue(ExternalLinks.isOpenable("https://wambito.com"))
        XCTAssertTrue(ExternalLinks.isOpenable("http://wambito.com"))
        XCTAssertTrue(ExternalLinks.isOpenable("mailto:a@b.c"))
        XCTAssertFalse(ExternalLinks.isOpenable("javascript:alert(1)"))
        XCTAssertFalse(ExternalLinks.isOpenable("wambito://add"))
        XCTAssertFalse(ExternalLinks.isOpenable("tel:123"))
        XCTAssertFalse(ExternalLinks.isOpenable(nil))
    }
}
