import UniformTypeIdentifiers
import XCTest
@testable import WambitoNative

final class PickerTypesTests: XCTestCase {
    func testMapsKnownMimeTypes() {
        XCTAssertEqual(PickerTypes.contentTypes(["text/csv"]), [.commaSeparatedText])
        XCTAssertEqual(PickerTypes.contentTypes(["text/plain"]), [.plainText])
    }

    func testOctetStreamIsAnyData() {
        XCTAssertEqual(PickerTypes.contentTypes(["application/octet-stream"]), [.data])
    }

    func testDropsUnknownAndNonStrings() {
        XCTAssertEqual(PickerTypes.contentTypes(["text/csv", "no/such-type-x", 7]), [.commaSeparatedText])
    }

    func testFallsBackWhenNothingMaps() {
        let fallback: [UTType] = [.commaSeparatedText, .plainText]
        XCTAssertEqual(PickerTypes.contentTypes(nil), fallback)
        XCTAssertEqual(PickerTypes.contentTypes([]), fallback)
        XCTAssertEqual(PickerTypes.contentTypes(["no/such-type-x"]), fallback)
    }

    func testNoDuplicates() {
        let types = PickerTypes.contentTypes(["text/csv", "text/csv", "text/comma-separated-values"])
        XCTAssertEqual(types.count, Set(types).count)
    }

    func testAnswerOnceRunsFirstOnly() {
        var calls = 0
        let once = AnswerOnce()
        XCTAssertTrue(once.run { calls += 1 })
        XCTAssertFalse(once.run { calls += 1 })
        XCTAssertEqual(calls, 1)
    }
}
