import Foundation

/// Money the way the app writes it, for the capture notification (no Flutter running): a port of
/// Android's `widget/Money.kt` `formatMoney`, itself `lib/money/format.dart`. `CaptureMoneyTests`
/// runs Android's `MoneyTest` cases.
public enum CaptureMoney {
  /// Every amount is stored in hundredths of the currency, whatever its ISO exponent.
  private static let minorUnit: Int64 = 100
  /// Currencies shown without decimals; stored in hundredths like the rest.
  private static let wholeUnit: Set<String> = ["COP", "CLP"]
  private static let minus = "\u{2212}"
  private static let nbsp = "\u{00A0}"

  private struct Style {
    let symbol: String
    let attached: Bool
  }

  /// Spanish, Italian and Portuguese write the decimal comma and the symbol after the figure.
  private static func commaLanguage(_ language: String) -> Bool { language != "en" }

  private static func style(_ currency: String, _ language: String) -> Style {
    let comma = commaLanguage(language)
    switch currency {
    case "COP":
      return language == "es" ? Style(symbol: "$", attached: true) : Style(symbol: "COP", attached: false)
    case "EUR":
      return Style(symbol: "€", attached: !comma)
    case "USD":
      if language == "it" { return Style(symbol: "USD", attached: false) }
      return comma ? Style(symbol: "US$", attached: false) : Style(symbol: "$", attached: true)
    default:
      return Style(symbol: currency, attached: false)
    }
  }

  /// [digits] with [separator] between groups of three; with [minTwo] four digits stay together.
  private static func grouped(_ digits: String, _ separator: String, minTwo: Bool) -> String {
    if digits.count <= 3 || (minTwo && digits.count == 4) { return digits }
    let chars = Array(digits)
    var out = ""
    let first = chars.count % 3
    if first > 0 { out += String(chars[0..<first]) }
    var i = first
    while i < chars.count {
      if !out.isEmpty { out += separator }
      out += String(chars[i..<(i + 3)])
      i += 3
    }
    return out
  }

  /// [cents] (hundredths) in [currency] for [language] ("es", "en", "it" or "pt").
  public static func format(cents: Int64, currency: String, language: String) -> String {
    let comma = commaLanguage(language)
    let style = style(currency, language)
    let whole = wholeUnit.contains(currency)
    let abs = cents.magnitude
    // Whole currencies round half away from zero, as Intl does.
    let units = whole ? (abs + UInt64(minorUnit / 2)) / UInt64(minorUnit) : abs / UInt64(minorUnit)
    let fractionValue = abs % UInt64(minorUnit)
    let fraction = fractionValue < 10 ? "0\(fractionValue)" : "\(fractionValue)"
    let colombian = currency == "COP" && language == "es"
    // Italian groups with a point, Portuguese (Portugal) with a no-break space, as Intl does.
    let group = language == "pt" ? nbsp : (comma ? "." : ",")
    var figure = grouped(String(units), group, minTwo: comma && !colombian)
    if !whole { figure += (comma ? "," : ".") + fraction }
    let zero = whole ? units == 0 : abs == 0
    let prefix = !zero && cents < 0 ? minus : ""
    if comma && !colombian { return "\(prefix)\(figure)\(nbsp)\(style.symbol)" }
    return "\(prefix)\(style.symbol)\(style.attached ? "" : nbsp)\(figure)"
  }
}
