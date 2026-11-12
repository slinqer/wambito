import XCTest

@testable import WambitoNative

final class NoticeTimesTests: XCTestCase {
  private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

  private func local(_ date: Date, _ zone: TimeZone) -> DateComponents {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
  }

  func testGuestWaitsFortyFourDays() {
    XCTAssertEqual(NoticeTimes.guestAfter, 44 * 86_400)
  }

  func testNextNineBeforeNineIsToday() {
    let bogota = TimeZone(identifier: "America/Bogota")!
    // 08:59 in Bogota (UTC-5) is 13:59 UTC.
    let next = NoticeTimes.nextNine(after: date("2026-11-11T13:59:00Z"), in: bogota)
    XCTAssertEqual(next, date("2026-11-11T14:00:00Z"))
  }

  func testNextNineAtNineIsTomorrow() {
    let bogota = TimeZone(identifier: "America/Bogota")!
    let next = NoticeTimes.nextNine(after: date("2026-11-11T14:00:00Z"), in: bogota)
    XCTAssertEqual(next, date("2026-11-12T14:00:00Z"))
  }

  func testNextNineAcrossDST() {
    let madrid = TimeZone(identifier: "Europe/Madrid")!
    // 2026-10-24 10:00 local (CEST, 08:00 UTC); the clocks go back on the 25th.
    let next = NoticeTimes.nextNine(after: date("2026-10-24T08:00:00Z"), in: madrid)
    XCTAssertEqual(next, date("2026-10-25T08:00:00Z"))
    let parts = local(next, madrid)
    XCTAssertEqual(parts.day, 25)
    XCTAssertEqual(parts.hour, 9)
    XCTAssertEqual(parts.minute, 0)
  }

  func testUnknownZoneFallsBack() {
    let utc = TimeZone(identifier: "UTC")!
    XCTAssertEqual(NoticeTimes.zone("Mars/Base", fallback: utc), utc)
    XCTAssertEqual(NoticeTimes.zone(nil, fallback: utc), utc)
    XCTAssertEqual(NoticeTimes.zone("  ", fallback: utc), utc)
    XCTAssertEqual(NoticeTimes.zone("Europe/Madrid", fallback: utc).identifier, "Europe/Madrid")
  }
}

final class NoticeTextTests: XCTestCase {
  private func join(_ names: [String]) -> String { NoticeText.join(names, and: "y", andI: "e") }

  func testOneName() { XCTAssertEqual(join(["Luz"]), "Luz") }
  func testTwoNames() { XCTAssertEqual(join(["Luz", "Agua"]), "Luz y Agua") }
  func testEBeforeTheSoundI() {
    XCTAssertEqual(join(["Luz", "Internet"]), "Luz e Internet")
    XCTAssertEqual(join(["Luz", "Higos"]), "Luz e Higos")
  }
  func testYBeforeAGlide() { XCTAssertEqual(join(["Luz", "Hielo"]), "Luz y Hielo") }
  func testThreeNames() { XCTAssertEqual(join(["Agua", "Luz", "Iva"]), "Agua, Luz e Iva") }
  func testBlanksAndDuplicatesDropped() { XCTAssertEqual(join(["Luz", " ", "Luz"]), "Luz") }
  func testNothingToJoin() { XCTAssertEqual(join([" "]), "") }
  func testStartsWithI() {
    XCTAssertTrue(NoticeText.startsWithI("Ítaca"))
    XCTAssertTrue(NoticeText.startsWithI("  \"Hipoteca\""))
    XCTAssertTrue(NoticeText.startsWithI("I"))
    XCTAssertFalse(NoticeText.startsWithI("Iatrogenia"))
    XCTAssertFalse(NoticeText.startsWithI("Luz"))
  }
}
