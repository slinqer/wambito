import XCTest

@testable import WambitoNative

final class DueScheduleTests: XCTestCase {
  private let bogota = TimeZone(identifier: "America/Bogota")!
  private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

  private let days: [(date: String, names: [String])] = [
    ("2026-11-16", ["Arriendo", "Spotify"]),
    ("2026-11-17", ["Gimnasio"]),
  ]

  func testTodayAtEightGetsTodaysNineOClock() {
    // 08:00 in Bogota is 13:00 UTC.
    let requests = DueSchedule.requests(
      days: days, zone: bogota, now: date("2026-11-16T13:00:00Z"))
    XCTAssertEqual(requests.map(\.id), ["wambito.due.2026-11-16", "wambito.due.2026-11-17"])
    let first = requests[0].fire
    XCTAssertEqual([first.year, first.month, first.day], [2026, 11, 16])
    XCTAssertEqual([first.hour, first.minute], [9, 0])
    XCTAssertEqual(first.timeZone, bogota)
  }

  func testTodayAtTenIsSkipped() {
    // 10:00 in Bogota is 15:00 UTC.
    let requests = DueSchedule.requests(
      days: days, zone: bogota, now: date("2026-11-16T15:00:00Z"))
    XCTAssertEqual(requests.map(\.id), ["wambito.due.2026-11-17"])
  }

  func testTodayAtExactlyNineIsSkipped() {
    let requests = DueSchedule.requests(
      days: days, zone: bogota, now: date("2026-11-16T14:00:00Z"))
    XCTAssertEqual(requests.map(\.id), ["wambito.due.2026-11-17"])
  }

  func testNamesKeepTheirOrder() {
    let requests = DueSchedule.requests(
      days: days, zone: bogota, now: date("2026-11-16T13:00:00Z"))
    XCTAssertEqual(requests[0].names, ["Arriendo", "Spotify"])
  }

  func testADayThatIsNotADateOrHasNoNamesIsLeftOut() {
    let requests = DueSchedule.requests(
      days: [("nope", ["A"]), ("2026-11-18", []), ("2026-11-19", ["  ", "B"])],
      zone: bogota, now: date("2026-11-16T13:00:00Z"))
    XCTAssertEqual(requests.map(\.id), ["wambito.due.2026-11-19"])
  }
}
