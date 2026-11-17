import XCTest

@testable import WambitoNative

final class SyncPlanTests: XCTestCase {
  func testAPreviewAccountSyncsFourHoursFromNow() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertEqual(
      SyncPlan.earliestBegin(mode: "preview", now: now), now.addingTimeInterval(4 * 3_600))
  }

  func testEveryOtherModeSchedulesNothing() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertNil(SyncPlan.earliestBegin(mode: "plain", now: now))
    XCTAssertNil(SyncPlan.earliestBegin(mode: "unknown", now: now))
    XCTAssertNil(SyncPlan.earliestBegin(mode: nil, now: now))
  }

  func testDoneChangedAndBusyAreSuccesses() {
    XCTAssertTrue(SyncPlan.succeeded("done"))
    XCTAssertTrue(SyncPlan.succeeded("changed"))
    XCTAssertTrue(SyncPlan.succeeded("busy"))
  }

  func testAnythingElseIsAFailure() {
    for outcome in ["failed", "timeout", "expired", "locked", "signedOut", "notPreview", ""] {
      XCTAssertFalse(SyncPlan.succeeded(outcome), outcome)
    }
  }
}
