import XCTest

@testable import WambitoNative

final class WalletPaymentTests: XCTestCase {
  private func amount(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

  func testPesosBecomeCents() {
    XCTAssertEqual(
      WalletPayment.read(amount: 18000, currencyCode: "COP", merchant: "Juan Valdez"),
      WalletPayment(cents: 1_800_000, currency: "COP", merchant: "Juan Valdez"))
  }

  func testEurosWithCentsALowercaseCodeAndSpaces() {
    XCTAssertEqual(
      WalletPayment.read(amount: amount("12.5"), currencyCode: "eur", merchant: " Mercadona  "),
      WalletPayment(cents: 1250, currency: "EUR", merchant: "Mercadona"))
  }

  func testMoreThanTwoDecimalsIsNeverRounded() {
    XCTAssertNil(WalletPayment.read(amount: amount("18000.005"), currencyCode: "COP", merchant: "A"))
  }

  func testZeroAndRefundsAreDropped() {
    XCTAssertNil(WalletPayment.read(amount: 0, currencyCode: "COP", merchant: "A"))
    XCTAssertNil(WalletPayment.read(amount: -5, currencyCode: "COP", merchant: "A"))
  }

  func testTheCurrencyIsExactlyThreeLetters() {
    for code in [nil, "", "CO", "PESOS", "C0P"] as [String?] {
      XCTAssertNil(WalletPayment.read(amount: 1, currencyCode: code, merchant: "A"), "\(code ?? "nil")")
    }
  }

  func testAnEmptyMerchantIsDropped() {
    XCTAssertNil(WalletPayment.read(amount: 1, currencyCode: "COP", merchant: nil))
    XCTAssertNil(WalletPayment.read(amount: 1, currencyCode: "COP", merchant: "   "))
  }

  func testAnAmountTooBigForCentsIsDropped() {
    XCTAssertNil(
      WalletPayment.read(amount: Decimal(Int64.max / 100) + 1, currencyCode: "COP", merchant: "A"))
  }
}
