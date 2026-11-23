import Foundation

/// A payment the Shortcuts Transaction automation handed to "Anotar pago de Wallet", read into
/// integer cents (spec 2026-11-22-ios-wallet-capture-design.md, section 3.1). Anything that is not a
/// clean charge is dropped (nil): never rounded, never guessed.
public struct WalletPayment: Equatable {
  /// Hundredths of [currency], always positive.
  public let cents: Int64
  /// ISO 4217, upper case.
  public let currency: String
  public let merchant: String

  public init(cents: Int64, currency: String, merchant: String) {
    self.cents = cents
    self.currency = currency
    self.merchant = merchant
  }

  /// The payment, or nil when the amount is not positive, has more than two decimals or does not
  /// fit, the currency is not three letters, or the merchant is empty.
  public static func read(amount: Decimal, currencyCode: String?, merchant: String?) -> WalletPayment? {
    guard let code = currencyCode?.trimmingCharacters(in: .whitespaces).uppercased(),
      code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter })
    else { return nil }
    guard let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
    else { return nil }
    guard amount > 0 else { return nil }
    let hundredths = NSDecimalNumber(decimal: amount).multiplying(byPowerOf10: 2)
    let whole = hundredths.rounding(
      accordingToBehavior: NSDecimalNumberHandler(
        roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: false,
        raiseOnUnderflow: false, raiseOnDivideByZero: false))
    guard whole == hundredths else { return nil }
    guard whole.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending else { return nil }
    return WalletPayment(cents: whole.int64Value, currency: code, merchant: name)
  }
}
