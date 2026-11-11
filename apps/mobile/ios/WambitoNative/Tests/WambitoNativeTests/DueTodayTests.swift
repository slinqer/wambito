import XCTest

@testable import WambitoNative

final class DueTodayTests: XCTestCase {
  private let bogota = TimeZone(identifier: "America/Bogota")!
  private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
  private func json(_ text: String) -> Data { Data(text.utf8) }

  // MARK: - The profile

  func testParseProfileWithZone() {
    let profile = DueToday.parseProfile(json(#"{"timezone":"America/Bogota","isAnonymous":false}"#))
    XCTAssertEqual(profile, DueToday.Profile(timezone: "America/Bogota", anonymous: false))
  }

  func testParseProfileWithoutZone() {
    let profile = DueToday.parseProfile(json(#"{"isAnonymous":true}"#))
    XCTAssertEqual(profile, DueToday.Profile(timezone: nil, anonymous: true))
  }

  func testParseProfileEmptyZoneIsNone() {
    let profile = DueToday.parseProfile(json(#"{"timezone":"","isAnonymous":false}"#))
    XCTAssertEqual(profile?.timezone, nil)
  }

  func testParseProfileWithoutGuestFlagFails() {
    XCTAssertNil(DueToday.parseProfile(json(#"{"timezone":"America/Bogota"}"#)))
    XCTAssertNil(DueToday.parseProfile(json("not json")))
  }

  // MARK: - The query

  func testQueryWithoutCursor() {
    XCTAssertEqual(
      DueToday.query(month: "2026-11", cursor: nil), "status=pending&month=2026-11&limit=200")
  }

  func testQueryWithCursor() {
    XCTAssertEqual(
      DueToday.query(month: "2026-11", cursor: "abc123"),
      "status=pending&month=2026-11&limit=200&cursor=abc123")
  }

  func testMaxPagesIsAndroids() {
    XCTAssertEqual(DueToday.maxPages, 10)
  }

  // MARK: - A page

  private let mixedPage = #"""
    {"items":[
      {"date":"2026-11-11","status":"pending","recurrenceId":"rec-1","createdAt":"2026-10-01T10:00:00Z","name":"Arriendo"},
      {"date":"2026-11-11","status":"paid","recurrenceId":"rec-2","createdAt":"2026-10-02T10:00:00Z","name":"Gimnasio"},
      {"date":"2026-11-11","status":"pending","recurrenceId":null,"createdAt":"2026-10-03T10:00:00Z","name":"Almuerzo"},
      {"date":"2026-11-10","status":"pending","recurrenceId":"rec-3","createdAt":"2026-10-04T10:00:00Z","name":"Internet"}
    ],"nextCursor":"next-1"}
    """#

  func testParsePageKeepsTodaysPendingRecurringAndStopsAtYesterday() {
    let page = DueToday.parsePage(json(mixedPage), today: "2026-11-11")
    XCTAssertEqual(page?.names.map(\.name), ["Arriendo"])
    XCTAssertEqual(page?.names.map(\.createdAt), ["2026-10-01T10:00:00Z"])
    XCTAssertEqual(page?.stop, true)
    XCTAssertEqual(page?.next, "next-1")
  }

  func testParsePageWithoutNextCursorStops() {
    let body = #"""
      {"items":[{"date":"2026-11-11","status":"pending","recurrenceId":"rec-1","createdAt":"c","name":"Spotify"}]}
      """#
    let page = DueToday.parsePage(json(body), today: "2026-11-11")
    XCTAssertEqual(page?.names.map(\.name), ["Spotify"])
    XCTAssertEqual(page?.stop, true)
    XCTAssertNil(page?.next)
  }

  func testParsePageOfTodayOnlyWithNextCursorGoesOn() {
    let body = #"""
      {"items":[{"date":"2026-11-11","status":"pending","recurrenceId":"","createdAt":"c","name":"Spotify"}],
       "nextCursor":"next-2"}
      """#
    let page = DueToday.parsePage(json(body), today: "2026-11-11")
    XCTAssertEqual(page?.names.count, 0)  // an empty recurrenceId is not a recurring payment
    XCTAssertEqual(page?.stop, false)
    XCTAssertEqual(page?.next, "next-2")
  }

  func testParsePageWithNoItemsStops() {
    let page = DueToday.parsePage(json(#"{"items":[],"nextCursor":"next-3"}"#), today: "2026-11-11")
    XCTAssertEqual(page?.stop, true)
  }

  func testParsePageUnreadableFails() {
    XCTAssertNil(DueToday.parsePage(json(#"{"nextCursor":null}"#), today: "2026-11-11"))
    XCTAssertNil(DueToday.parsePage(json(#"{"items":[{"name":"No date"}]}"#), today: "2026-11-11"))
  }

  // MARK: - Order and words

  func testOrderedByCreatedAtThenName() {
    let names = [
      (createdAt: "2026-11-02", name: "B"), (createdAt: "2026-11-01", name: "C"),
      (createdAt: "2026-11-01", name: "A"),
    ]
    XCTAssertEqual(DueToday.ordered(names), ["A", "C", "B"])
  }

  func testTextOneAndMany() {
    func text(_ names: [String]) -> String {
      DueToday.text(names, one: "Hoy vence %@", many: "Hoy vencen %@", and: "y", andI: "e")
    }
    XCTAssertEqual(text(["Arriendo"]), "Hoy vence Arriendo")
    XCTAssertEqual(text(["Arriendo", " Arriendo "]), "Hoy vence Arriendo")
    XCTAssertEqual(text(["Arriendo", "Internet"]), "Hoy vencen Arriendo e Internet")
    XCTAssertEqual(text(["Arriendo", "Spotify", "Gas"]), "Hoy vencen Arriendo, Spotify y Gas")
    XCTAssertEqual(text([" "]), "")
  }

  // MARK: - The server

  func testServerOfSetting() {
    XCTAssertEqual(
      DueToday.server(.notChosen, fallback: "https://app.wambito.com"), "https://app.wambito.com")
    XCTAssertEqual(
      DueToday.server(.chosen("https://mine.example"), fallback: "https://app.wambito.com"),
      "https://mine.example")
    // Stored but unreadable: never guessed, so the token never goes to another server.
    XCTAssertNil(DueToday.server(.unreadable, fallback: "https://app.wambito.com"))
    XCTAssertNil(DueToday.server(.notChosen, fallback: nil))
  }

  func testURLOfServerAndPath() {
    XCTAssertEqual(
      DueToday.url(server: "https://mine.example/", path: "/v1/me")?.absoluteString,
      "https://mine.example/api/v1/me")
    XCTAssertEqual(
      DueToday.url(server: "http://10.0.2.2:3000", path: "/v1/transactions?status=pending")?
        .absoluteString,
      "http://10.0.2.2:3000/api/v1/transactions?status=pending")
    XCTAssertNil(DueToday.url(server: "ftp://mine.example", path: "/v1/me"))
    XCTAssertNil(DueToday.url(server: "", path: "/v1/me"))
  }

  // MARK: - A run

  private let me = #"{"timezone":"America/Bogota","isAnonymous":false}"#
  private let todayPage = #"""
    {"items":[
      {"date":"2026-11-11","status":"pending","recurrenceId":"rec-2","createdAt":"2026-10-02","name":"Spotify"},
      {"date":"2026-11-11","status":"pending","recurrenceId":"rec-1","createdAt":"2026-10-01","name":"Arriendo"},
      {"date":"2026-11-09","status":"pending","recurrenceId":"rec-3","createdAt":"2026-10-03","name":"Gas"}
    ],"nextCursor":"more"}
    """#

  /// A fake server: the answer for each path, in order of the calls.
  private final class Server {
    var answers: [String: DueToday.Answer]
    var asked: [String] = []
    init(_ answers: [String: DueToday.Answer]) { self.answers = answers }
    func get(_ path: String) async -> DueToday.Answer {
      asked.append(path)
      return answers[path] ?? .failed
    }
  }

  private let firstPage = "/v1/transactions?status=pending&month=2026-11&limit=200"

  func testRunAfterNineFindsTheNames() async {
    let server = Server(["/v1/me": .ok(json(me)), firstPage: .ok(json(todayPage))])
    // 10:00 in Bogota.
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: .gmt, lastDay: "2026-11-10", get: server.get)
    XCTAssertEqual(run.outcome, .due(["Arriendo", "Spotify"]))
    XCTAssertEqual(run.zone, bogota)
    XCTAssertEqual(run.today, "2026-11-11")
    XCTAssertTrue(run.keepGoing)
    XCTAssertEqual(server.asked, ["/v1/me", firstPage])
  }

  func testRunFollowsTheCursor() async {
    let first = #"""
      {"items":[{"date":"2026-11-11","status":"pending","recurrenceId":"r","createdAt":"2","name":"B"}],
       "nextCursor":"c2"}
      """#
    let second = #"""
      {"items":[{"date":"2026-11-11","status":"pending","recurrenceId":"r","createdAt":"1","name":"A"}],
       "nextCursor":null}
      """#
    let server = Server([
      "/v1/me": .ok(json(me)), firstPage: .ok(json(first)), firstPage + "&cursor=c2": .ok(json(second)),
    ])
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: .gmt, lastDay: nil, get: server.get)
    XCTAssertEqual(run.outcome, .due(["A", "B"]))
  }

  func testRunWithNothingDue() async {
    let server = Server(["/v1/me": .ok(json(me)), firstPage: .ok(json(#"{"items":[]}"#))])
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: .gmt, lastDay: nil, get: server.get)
    XCTAssertEqual(run.outcome, .nothingDue)
    XCTAssertTrue(run.keepGoing)
  }

  func testRunBeforeNineAsksForNoPayments() async {
    let server = Server(["/v1/me": .ok(json(me))])
    // 08:30 in Bogota.
    let run = await DueToday.run(
      now: date("2026-11-11T13:30:00Z"), known: .gmt, lastDay: nil, get: server.get)
    XCTAssertEqual(run.outcome, .beforeNine)
    XCTAssertEqual(run.zone, bogota)
    XCTAssertEqual(server.asked, ["/v1/me"])
  }

  func testRunAlreadyToday() async {
    let server = Server(["/v1/me": .ok(json(me))])
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: .gmt, lastDay: "2026-11-11", get: server.get)
    XCTAssertEqual(run.outcome, .alreadyToday)
    XCTAssertEqual(server.asked, ["/v1/me"])
  }

  func testRunSignedOutStops() async {
    let server = Server(["/v1/me": .unauthorized])
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: bogota, lastDay: nil, get: server.get)
    XCTAssertEqual(run.outcome, .signedOut)
    XCTAssertFalse(run.keepGoing)
  }

  func testRunSignedOutOnThePaymentsStops() async {
    let server = Server(["/v1/me": .ok(json(me)), firstPage: .unauthorized])
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: .gmt, lastDay: nil, get: server.get)
    XCTAssertEqual(run.outcome, .signedOut)
    XCTAssertFalse(run.keepGoing)
  }

  func testRunFailureGoesOnTomorrow() async {
    let offline = Server([:])
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: bogota, lastDay: nil, get: offline.get)
    XCTAssertEqual(run.outcome, .failed)
    XCTAssertTrue(run.keepGoing)
    XCTAssertEqual(run.zone, bogota)

    let broken = Server(["/v1/me": .ok(json(me)), firstPage: .ok(json("<html>"))])
    let later = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: .gmt, lastDay: nil, get: broken.get)
    XCTAssertEqual(later.outcome, .failed)
    XCTAssertTrue(later.keepGoing)
  }

  func testRunGivesUpAfterMaxPages() async {
    let endless = #"""
      {"items":[{"date":"2026-11-11","status":"pending","recurrenceId":"r","createdAt":"1","name":"A"}],
       "nextCursor":"again"}
      """#
    let server = Server([
      "/v1/me": .ok(json(me)), firstPage: .ok(json(endless)),
      firstPage + "&cursor=again": .ok(json(endless)),
    ])
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: .gmt, lastDay: nil, get: server.get)
    XCTAssertEqual(run.outcome, .failed)
    XCTAssertEqual(server.asked.count, 1 + DueToday.maxPages)
  }

  func testRunUnknownProfileZoneKeepsTheKnownOne() async {
    let server = Server([
      "/v1/me": .ok(json(#"{"timezone":"Mars/Olympus","isAnonymous":false}"#)),
      firstPage: .ok(json(#"{"items":[]}"#)),
    ])
    let run = await DueToday.run(
      now: date("2026-11-11T15:00:00Z"), known: bogota, lastDay: nil, get: server.get)
    XCTAssertEqual(run.zone, bogota)
    XCTAssertEqual(run.outcome, .nothingDue)
  }

  func testDayInZone() {
    // 03:00 UTC on the 12th is still the 11th in Bogota.
    XCTAssertEqual(DueToday.day(date("2026-11-12T03:00:00Z"), in: bogota), "2026-11-11")
  }
}
