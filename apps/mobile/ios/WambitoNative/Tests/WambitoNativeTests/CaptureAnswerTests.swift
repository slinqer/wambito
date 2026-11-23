import XCTest

@testable import WambitoNative

final class CaptureAnswerTests: XCTestCase {
  private let noted = "Anoté %@ en %@ · %@, ¿bien?"
  private let fallback = "Anoté %@ en %@ · %@, ¿qué categoría?"

  private func answer(result: String = "created", fallback: Bool = false, needsReview: Any? = true)
    -> [String: Any]
  {
    var transaction: [String: Any] = [
      "id": "tx-1", "amount": -1_800_000, "currency": "COP", "name": "Juan Valdez",
    ]
    if let needsReview { transaction["needsReview"] = needsReview }
    return [
      "result": result, "transaction": transaction,
      "category": ["name": fallback ? "Otros gastos" : "Café", "fallback": fallback],
    ]
  }

  func testACreatedAnswer() {
    let read = CaptureAnswer.parse(answer())
    XCTAssertEqual(
      read,
      CaptureAnswer(
        id: "tx-1", cents: -1_800_000, currency: "COP", name: "Juan Valdez", categoryName: "Café",
        isFallback: false, merged: false, needsReview: true))
  }

  func testAMergedAnswerAlreadyConfirmed() {
    let read = CaptureAnswer.parse(answer(result: "merged", needsReview: false))
    XCTAssertEqual(read?.merged, true)
    XCTAssertEqual(read?.needsReview, false)
  }

  func testAnAnswerThatDoesNotSayNeedsReviewStillAsks() {
    XCTAssertEqual(CaptureAnswer.parse(answer(needsReview: nil))?.needsReview, true)
  }

  func testAnotherShapeIsNil() {
    var broken = answer()
    broken["transaction"] = ["amount": 1]
    XCTAssertNil(CaptureAnswer.parse(broken))
    XCTAssertNil(CaptureAnswer.parse(["result": "created"]))
  }

  func testTheNoticeAsksBien() {
    let read = CaptureAnswer.parse(answer())!
    XCTAssertEqual(
      read.noted(template: noted, fallbackTemplate: fallback, language: "es"),
      "Anoté −$18.000 en Juan Valdez · Café, ¿bien?")
  }

  func testANewMerchantAsksTheCategory() {
    let read = CaptureAnswer.parse(answer(fallback: true))!
    XCTAssertEqual(
      read.noted(template: noted, fallbackTemplate: fallback, language: "es"),
      "Anoté −$18.000 en Juan Valdez · Otros gastos, ¿qué categoría?")
  }

  func testIncomeCarriesAPlus() {
    var income = answer()
    income["transaction"] = ["id": "tx-2", "amount": 5_000_000, "currency": "COP", "name": "Nómina"]
    XCTAssertEqual(
      CaptureAnswer.parse(income)!.noted(template: noted, fallbackTemplate: fallback, language: "es"),
      "Anoté +$50.000 en Nómina · Café, ¿bien?")
  }

  func testTheNoticeIdAndLinkComeFromTheTransaction() {
    XCTAssertEqual(CaptureAnswer.noticeId("tx-1"), "wambito.capture.tx-1")
    XCTAssertEqual(CaptureAnswer.parse(answer())?.link, "wambito://review/tx-1")
  }
}
