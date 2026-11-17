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

  func testTheOwnerIsKeptUnderWambitoDotEncryptionDotOwnerAndClearedWithTheMode() throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "AccountModeOwnerTests"))
    defaults.removePersistentDomain(forName: "AccountModeOwnerTests")
    XCTAssertNil(AccountMode.owner(defaults))
    AccountMode.write("preview", owner: "user-1", defaults: defaults)
    XCTAssertEqual(AccountMode.owner(defaults), "user-1")
    XCTAssertEqual(defaults.string(forKey: "wambito.encryption.owner"), "user-1")
    // A mode without an owner (signed in, no session read yet) keeps no owner.
    AccountMode.write("unknown", owner: nil, defaults: defaults)
    XCTAssertNil(AccountMode.owner(defaults))
    AccountMode.write("preview", owner: "user-2", defaults: defaults)
    AccountMode.write(nil, owner: "user-2", defaults: defaults)
    XCTAssertNil(AccountMode.read(defaults))
    XCTAssertNil(AccountMode.owner(defaults))
  }
}
