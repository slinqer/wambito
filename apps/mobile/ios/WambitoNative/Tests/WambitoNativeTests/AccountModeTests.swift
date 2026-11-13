import XCTest

@testable import WambitoNative

final class AccountModeTests: XCTestCase {
  func testOnlyPlainOrNothingWrittenLetsARunReachTheApi() {
    XCTAssertTrue(AccountMode.allowsApi(nil))
    XCTAssertTrue(AccountMode.allowsApi("plain"))
    XCTAssertFalse(AccountMode.allowsApi("preview"))
    XCTAssertFalse(AccountMode.allowsApi("unknown"))
    XCTAssertFalse(AccountMode.allowsApi("anything else"))
  }

  func testPreviewStopsTheDailyRunForGood() {
    XCTAssertEqual(AccountMode.dueRun(nil), .ask)
    XCTAssertEqual(AccountMode.dueRun("plain"), .ask)
    XCTAssertEqual(AccountMode.dueRun("preview"), .stop)
    // Signed in but the app has not learned the mode: nothing today, tomorrow looks again.
    XCTAssertEqual(AccountMode.dueRun("unknown"), .skipToday)
  }

  func testTheModeIsKeptUnderWambitoDotEncryptionDotMode() throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "AccountModeTests"))
    defaults.removePersistentDomain(forName: "AccountModeTests")
    XCTAssertNil(AccountMode.read(defaults))
    AccountMode.write("preview", defaults: defaults)
    XCTAssertEqual(AccountMode.read(defaults), "preview")
    XCTAssertEqual(defaults.string(forKey: "wambito.encryption.mode"), "preview")
    AccountMode.write(nil, defaults: defaults)
    XCTAssertNil(AccountMode.read(defaults))
  }
}
