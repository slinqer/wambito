import XCTest

@testable import WambitoNative

final class LiveDecodeTests: XCTestCase {
  func testScheduleFirstAtOneSecond() {
    var s = LiveSchedule()
    XCTAssertFalse(s.shouldDecode(samples: 15_360, busy: false))
    XCTAssertTrue(s.shouldDecode(samples: 16_000, busy: false))
    XCTAssertFalse(s.shouldDecode(samples: 23_680, busy: false))
    XCTAssertTrue(s.shouldDecode(samples: 24_000, busy: false))
  }

  func testScheduleWaitsWhileBusy() {
    var s = LiveSchedule()
    XCTAssertFalse(s.shouldDecode(samples: 16_000, busy: true))
    XCTAssertTrue(s.shouldDecode(samples: 16_640, busy: false))
    XCTAssertFalse(s.shouldDecode(samples: 24_000, busy: false))
    XCTAssertTrue(s.shouldDecode(samples: 24_640, busy: false))
  }

  func testLastWordHiddenWhileRecording() {
    XCTAssertEqual(LiveText.shown(" dieciocho lukas almu ", final: false), "dieciocho lukas")
  }

  func testLastWordKeptAtTheEnd() {
    XCTAssertEqual(
      LiveText.shown("dieciocho lukas almuerzo ", final: true), "dieciocho lukas almuerzo")
  }

  func testOneWordIsEmptyWhileRecording() {
    XCTAssertEqual(LiveText.shown("diec", final: false), "")
  }

  func testMemoryRule() {
    XCTAssertTrue(MemoryRule.qualifies(physical: 3 << 30, minimum: nil))
    XCTAssertFalse(MemoryRule.qualifies(physical: (3 << 30) - 1, minimum: nil))
    XCTAssertFalse(MemoryRule.qualifies(physical: 4 << 30, minimum: 5 << 30))
  }

  func testMemoryRuleNeverBelowTheDefault() {
    // As Kotlin's max(minRam, MIN_RAM): a smaller minimum does not lower the floor.
    XCTAssertFalse(MemoryRule.qualifies(physical: (5 << 30) / 2, minimum: 2 << 30))
    XCTAssertTrue(MemoryRule.qualifies(physical: 3 << 30, minimum: 2 << 30))
  }
}
