import XCTest

@testable import WambitoNative

/// The cases of Android's MoneyTest.kt (widget/Money.kt), so both phones write money alike.
final class CaptureMoneyTests: XCTestCase {
  private let nbsp = "\u{00A0}"

  func testEveryCaseOfAndroid() {
    XCTAssertEqual(CaptureMoney.format(cents: 5000000, currency: "COP", language: "es"), "$50.000")
    XCTAssertEqual(CaptureMoney.format(cents: 430000000, currency: "COP", language: "es"), "$4.300.000")
    XCTAssertEqual(CaptureMoney.format(cents: 5000000, currency: "COP", language: "en"), "COP\(nbsp)50,000")
    XCTAssertEqual(CaptureMoney.format(cents: 0, currency: "COP", language: "es"), "$0")
    XCTAssertEqual(CaptureMoney.format(cents: 56292, currency: "EUR", language: "es"), "562,92\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 56292, currency: "EUR", language: "en"), "€562.92")
    XCTAssertEqual(CaptureMoney.format(cents: 123456, currency: "EUR", language: "en"), "€1,234.56")
    XCTAssertEqual(CaptureMoney.format(cents: 56292, currency: "USD", language: "es"), "562,92\(nbsp)US$")
    XCTAssertEqual(CaptureMoney.format(cents: 123456, currency: "USD", language: "en"), "$1,234.56")
    XCTAssertEqual(CaptureMoney.format(cents: 123456, currency: "EUR", language: "es"), "1234,56\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 1234500, currency: "EUR", language: "es"), "12.345,00\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 430000000, currency: "EUR", language: "es"), "4.300.000,00\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 123456, currency: "COP", language: "es"), "$1.235")
    XCTAssertEqual(CaptureMoney.format(cents: -608, currency: "EUR", language: "es"), "−6,08\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: -608, currency: "EUR", language: "en"), "−€6.08")
    XCTAssertEqual(CaptureMoney.format(cents: -5000000, currency: "COP", language: "es"), "−$50.000")
    XCTAssertEqual(CaptureMoney.format(cents: -5000000, currency: "COP", language: "en"), "−COP\(nbsp)50,000")
    XCTAssertEqual(CaptureMoney.format(cents: -5, currency: "COP", language: "es"), "$0")
    XCTAssertEqual(CaptureMoney.format(cents: 150, currency: "COP", language: "es"), "$2")
    XCTAssertEqual(CaptureMoney.format(cents: 56292, currency: "COP", language: "es"), "$563")
    XCTAssertEqual(CaptureMoney.format(cents: -150, currency: "COP", language: "es"), "−$2")
    XCTAssertEqual(CaptureMoney.format(cents: 5000000, currency: "CLP", language: "es"), "50.000\(nbsp)CLP")
    XCTAssertEqual(CaptureMoney.format(cents: 5000000, currency: "CLP", language: "en"), "CLP\(nbsp)50,000")
    XCTAssertEqual(CaptureMoney.format(cents: 123450, currency: "EUR", language: "it"), "1234,50\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 123450, currency: "EUR", language: "pt"), "1234,50\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 56292, currency: "EUR", language: "pt"), "562,92\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 0, currency: "EUR", language: "it"), "0,00\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 1234500, currency: "EUR", language: "it"), "12.345,00\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 430000000, currency: "EUR", language: "it"), "4.300.000,00\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 1234500, currency: "EUR", language: "pt"), "12\(nbsp)345,00\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 430000000, currency: "EUR", language: "pt"), "4\(nbsp)300\(nbsp)000,00\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: -608, currency: "EUR", language: "pt"), "−6,08\(nbsp)€")
    XCTAssertEqual(CaptureMoney.format(cents: 123400, currency: "USD", language: "it"), "1234,00\(nbsp)USD")
    XCTAssertEqual(CaptureMoney.format(cents: 123400, currency: "USD", language: "pt"), "1234,00\(nbsp)US$")
    XCTAssertEqual(CaptureMoney.format(cents: 5000000, currency: "COP", language: "it"), "50.000\(nbsp)COP")
    XCTAssertEqual(CaptureMoney.format(cents: 5000000, currency: "COP", language: "pt"), "50\(nbsp)000\(nbsp)COP")
    XCTAssertEqual(CaptureMoney.format(cents: 5000000, currency: "CLP", language: "it"), "50.000\(nbsp)CLP")
  }
}

final class CaptureLanguageTests: XCTestCase {
  func testTheAppsLanguageThenThePhonesThenSpanish() {
    XCTAssertEqual(CaptureMoney.language(app: "it", phone: "en"), "it")
    XCTAssertEqual(CaptureMoney.language(app: nil, phone: "en"), "en")
    XCTAssertEqual(CaptureMoney.language(app: "de", phone: "pt"), "pt")
    XCTAssertEqual(CaptureMoney.language(app: nil, phone: "fr"), "es")
    XCTAssertEqual(CaptureMoney.language(app: nil, phone: nil), "es")
  }
}
