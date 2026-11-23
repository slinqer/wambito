import Foundation

/// What saving a capture answered (`{result, transaction, category}` of the local `POST
/// /v1/captures`, handed back by `captureMain`'s `finished`): a port of Android's
/// `parseCaptureAnswer` (CaptureApi.kt). It is what the "¿bien?" notification says.
public struct CaptureAnswer: Equatable {
  public let id: String
  /// Signed hundredths: an expense is negative.
  public let cents: Int64
  public let currency: String
  public let name: String
  public let categoryName: String
  /// The category is the kind's fallback ("Otros gastos"): the merchant is new.
  public let isFallback: Bool
  /// The same payment was already saved (the duplicate window).
  public let merged: Bool
  /// The transaction still waits for "¿bien?"; false only for a merged one already confirmed.
  public let needsReview: Bool

  public init(
    id: String, cents: Int64, currency: String, name: String, categoryName: String,
    isFallback: Bool, merged: Bool, needsReview: Bool
  ) {
    self.id = id
    self.cents = cents
    self.currency = currency
    self.name = name
    self.categoryName = categoryName
    self.isFallback = isFallback
    self.merged = merged
    self.needsReview = needsReview
  }

  /// The answer, or nil when it is not that shape.
  public static func parse(_ json: [String: Any]) -> CaptureAnswer? {
    guard let result = json["result"] as? String,
      let transaction = json["transaction"] as? [String: Any],
      let category = json["category"] as? [String: Any],
      let id = transaction["id"] as? String,
      let amount = (transaction["amount"] as? NSNumber)?.int64Value,
      let currency = transaction["currency"] as? String,
      let name = transaction["name"] as? String,
      let categoryName = category["name"] as? String,
      let fallback = category["fallback"] as? Bool
    else { return nil }
    return CaptureAnswer(
      id: id, cents: amount, currency: currency, name: name, categoryName: categoryName,
      isFallback: fallback, merged: result == "merged",
      // One that does not say is asked again, as before the field existed.
      needsReview: transaction["needsReview"] as? Bool ?? true)
  }

  /// The notification's id: one per transaction, so a merged answer replaces it.
  public static func noticeId(_ transactionId: String) -> String { "wambito.capture.\(transactionId)" }

  /// Where "Cambiar" and a tap go.
  public var link: String { "wambito://review/\(id)" }

  /// "Anoté −$18.000 en Juan Valdez · Café, ¿bien?": the templates are `Notices.strings`'
  /// `capture_noted` / `capture_noted_fallback`, money, merchant and category in that order.
  public func noted(template: String, fallbackTemplate: String, language: String) -> String {
    let sign = cents > 0 ? "+" : ""
    let money = sign + CaptureMoney.format(cents: cents, currency: currency, language: language)
    var text = isFallback ? fallbackTemplate : template
    for value in [money, name, categoryName] {
      guard let range = text.range(of: "%@") else { break }
      text.replaceSubrange(range, with: value)
    }
    return text
  }
}
