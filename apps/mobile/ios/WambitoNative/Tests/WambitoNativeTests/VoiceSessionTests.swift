import XCTest

@testable import WambitoNative

final class VoiceSessionTests: XCTestCase {
  func testBeginRecords() {
    var session = VoiceSession()
    XCTAssertEqual(session.begin(), [.category(record: true), .activate])
  }

  func testEndAfterBeginRestores() {
    var session = VoiceSession()
    _ = session.begin()
    XCTAssertEqual(session.end(), [.category(record: false), .deactivateNotifyingOthers])
  }

  func testSecondEndIsEmpty() {
    var session = VoiceSession()
    _ = session.begin()
    _ = session.end()
    XCTAssertEqual(session.end(), [])
  }

  func testEndWithoutBeginIsEmpty() {
    var session = VoiceSession()
    XCTAssertEqual(session.end(), [])
  }

  func testBeginTwiceIsOneSession() {
    var session = VoiceSession()
    _ = session.begin()
    XCTAssertEqual(session.begin(), [])
    XCTAssertEqual(session.end(), [.category(record: false), .deactivateNotifyingOthers])
    XCTAssertEqual(session.end(), [])
  }

  func testBeginAgainAfterEnd() {
    var session = VoiceSession()
    _ = session.begin()
    _ = session.end()
    XCTAssertEqual(session.begin(), [.category(record: true), .activate])
  }
}

final class SessionStepApplyTests: XCTestCase {
  private struct Refused: Error {}

  func testEveryStepRunsWhenOneFails() {
    var ran: [SessionStep] = []
    let failed = SessionStep.applyEach([.category(record: false), .deactivateNotifyingOthers]) { step in
      ran.append(step)
      if step == .category(record: false) { throw Refused() }
    }
    XCTAssertEqual(ran, [.category(record: false), .deactivateNotifyingOthers])
    XCTAssertEqual(failed, [.category(record: false)])
  }

  func testNothingFailsWhenAllRun() {
    let failed = SessionStep.applyEach([.category(record: true), .activate]) { _ in }
    XCTAssertEqual(failed, [])
  }
}
