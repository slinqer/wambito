import XCTest
@testable import WambitoNative

final class CameraAccessTests: XCTestCase {
    // AVAuthorizationStatus: notDetermined 0, restricted 1, denied 2, authorized 3.
    func testAuthorizedIsGranted() {
        XCTAssertEqual(CameraAccess.state(3), "granted")
    }

    func testNotDeterminedAsks() {
        XCTAssertEqual(CameraAccess.state(0), "ask")
    }

    func testDeniedIsDenied() {
        XCTAssertEqual(CameraAccess.state(2), "denied")
    }

    func testRestrictedIsDenied() {
        // A parent's or an organisation's restriction: the person cannot grant it from the prompt.
        XCTAssertEqual(CameraAccess.state(1), "denied")
    }

    func testAnUnknownStatusIsNeverGranted() {
        XCTAssertEqual(CameraAccess.state(4), "denied")
        XCTAssertEqual(CameraAccess.state(-1), "denied")
    }
}
