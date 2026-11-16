import XCTest

@testable import WambitoNative

final class TaskOnceTests: XCTestCase {
  func testAFreshTaskMayStartAndEndsOnce() {
    let once = TaskOnce()
    XCTAssertTrue(once.mayStart)
    XCTAssertTrue(once.end())
    XCTAssertFalse(once.end())
    XCTAssertFalse(once.mayStart, "an ended task never starts an engine")
  }

  func testAnExpirationBeforeTheStartKeepsTheEngineFromStarting() {
    let once = TaskOnce()
    XCTAssertTrue(once.abort(), "the expiration ends the task")
    XCTAssertFalse(once.mayStart)
    XCTAssertFalse(once.end(), "the run's own end comes too late")
  }

  func testAnExpirationAfterTheEndEndsNothingMore() {
    let once = TaskOnce()
    XCTAssertTrue(once.end())
    XCTAssertFalse(once.abort())
  }
}
