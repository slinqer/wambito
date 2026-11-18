import XCTest

@testable import WambitoNative

final class QrPrefixTests: XCTestCase {
  private let pair = "wambito://pair?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abc"
  private let signin = "wambito://signin?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abc"

  func testTheDefaultTakesThePairingQrOnly() {
    let prefixes = QrPrefix.of(nil)
    XCTAssertEqual(prefixes, [QrPrefix.pair])
    XCTAssertTrue(QrPrefix.accepts(pair, prefixes: prefixes))
    XCTAssertFalse(QrPrefix.accepts(signin, prefixes: prefixes))
  }

  func testTheSigninQrWhenAsked() {
    let prefixes = QrPrefix.of([QrPrefix.signin])
    XCTAssertTrue(QrPrefix.accepts(signin, prefixes: prefixes))
    XCTAssertFalse(QrPrefix.accepts(pair, prefixes: prefixes))
    XCTAssertTrue(QrPrefix.accepts(pair, prefixes: QrPrefix.of([QrPrefix.pair, QrPrefix.signin])))
  }

  func testAForeignTextNeverWhateverIsAsked() {
    let asked = QrPrefix.of(["https://", "", "wambito://", 7, QrPrefix.signin])
    XCTAssertEqual(asked, [QrPrefix.signin])
    for text in ["https://evil.example/x", "", "wambito://add", "WAMBITO://signin?id=1"] {
      XCTAssertFalse(QrPrefix.accepts(text, prefixes: asked))
      XCTAssertFalse(QrPrefix.accepts(text, prefixes: ["https://", "", "wambito://"]))
    }
    XCTAssertEqual(QrPrefix.of(["https://"]), [QrPrefix.pair])
    XCTAssertEqual(QrPrefix.of("wambito://signin?"), [QrPrefix.pair])
  }
}
