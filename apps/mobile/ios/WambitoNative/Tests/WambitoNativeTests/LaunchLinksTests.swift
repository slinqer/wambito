import Foundation
import XCTest

@testable import WambitoNative

final class LaunchLinksTests: XCTestCase {
  private func link(_ address: String) -> String? {
    LaunchLinks.linkOf(URL(string: address)!)
  }

  func testAcceptsTheAppLinks() {
    XCTAssertEqual(link("wambito://add"), "wambito://add")
    XCTAssertEqual(link("wambito://capture"), "wambito://capture")
    XCTAssertEqual(link("wambito://due"), "wambito://due")
    XCTAssertEqual(link("wambito://progress"), "wambito://progress")
    XCTAssertEqual(link("wambito://home/"), "wambito://home/")
    XCTAssertEqual(link("wambito://review/abc"), "wambito://review/abc")
  }

  func testRefusesWhatIsNotAnAppLink() {
    XCTAssertNil(link("wambito://review"))
    XCTAssertNil(link("wambito://review/"))
    XCTAssertNil(link("wambito://review/a/b"))
    XCTAssertNil(link("wambito://add/x"))
    XCTAssertNil(link("wambito://other"))
    XCTAssertNil(link("https://app.wambito.com/add"))
    XCTAssertNil(link("https://app.wambito.com/auth/verify"))
  }

  func testAcceptsTheSigninQrWithItsQueryOnly() {
    let qr =
      "wambito://signin?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"
    XCTAssertEqual(link(qr), qr)
    XCTAssertNil(link("wambito://signin"))
    XCTAssertNil(link("wambito://signin/x?id=1"))
    XCTAssertNil(link("https://app.wambito.com/signin?id=1"))
  }

  func testTakeReturnsTheLinkOnce() {
    let pending = PendingLink()
    XCTAssertTrue(pending.keep(URL(string: "wambito://add")!))
    XCTAssertEqual(pending.take(), "wambito://add")
    XCTAssertNil(pending.take())
  }

  func testKeepRefusesAndKeepsNothing() {
    let pending = PendingLink()
    XCTAssertFalse(pending.keep(URL(string: "wambito://other")!))
    XCTAssertNil(pending.take())
  }

  func testALinkWhileRunningIsKeptAndAnnounced() {
    let pending = PendingLink()
    var announced = 0
    pending.onKept = { announced += 1 }
    XCTAssertTrue(pending.keep(URL(string: "wambito://capture")!))
    XCTAssertEqual(announced, 1)
    XCTAssertFalse(pending.keep(URL(string: "wambito://other")!))
    XCTAssertEqual(announced, 1)
    XCTAssertEqual(pending.take(), "wambito://capture")
  }

  func testANoticeTapOpensItsLink() {
    XCTAssertEqual(LaunchLinks.noticeTap(["link": "due"])?.absoluteString, "wambito://due")
    XCTAssertEqual(LaunchLinks.noticeTap(["link": "progress"])?.absoluteString, "wambito://progress")
    XCTAssertNil(LaunchLinks.noticeTap([:]))
    XCTAssertNil(LaunchLinks.noticeTap(["link": ""]))
    XCTAssertNil(LaunchLinks.noticeTap(["link": 7]))
  }
}
