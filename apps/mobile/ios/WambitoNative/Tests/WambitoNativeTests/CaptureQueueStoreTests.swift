import XCTest

@testable import WambitoNative

final class CaptureQueueStoreTests: XCTestCase {
  private var file: URL!
  private let coffee = WalletPayment(cents: 1_800_000, currency: "COP", merchant: "Juan Valdez")
  private let at = Date(timeIntervalSince1970: 1_795_449_600.25)

  override func setUp() {
    file = FileManager.default.temporaryDirectory
      .appendingPathComponent("queue-\(UUID().uuidString)")
      .appendingPathComponent("wambito.capture.queue.json")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
  }

  private func store() -> CaptureQueueStore { CaptureQueueStore(file: file) }

  func testAnItemHasTheShapeDartReads() {
    let queue = store()
    queue.adopt(userId: "u1", from: nil)
    let key = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    let taken = queue.take(userId: "u1")
    XCTAssertEqual(taken.confirms, [])
    XCTAssertEqual(taken.captures.count, 1)
    let item = taken.captures[0]
    XCTAssertEqual(item["key"] as? String, key)
    XCTAssertEqual(item["kind"] as? String, "expense")
    XCTAssertEqual(item["amount"] as? Int, 1_800_000)
    XCTAssertEqual(item["currency"] as? String, "COP")
    XCTAssertEqual(item["merchant"] as? String, "Juan Valdez")
    XCTAssertEqual(item["capturedAt"] as? String, "2026-11-23T16:00:00.250Z")
    XCTAssertEqual(item["source"] as? String, "apple_wallet")
    XCTAssertNil(item["user"])
  }

  func testTakeLeavesTheQueueAsItIs() {
    let queue = store()
    queue.adopt(userId: "u1", from: nil)
    _ = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    _ = queue.take(userId: "u1")
    XCTAssertEqual(queue.take(userId: "u1").captures.count, 1)
  }

  func testTheQueueSurvivesARestart() {
    store().adopt(userId: "u1", from: nil)
    _ = store().add(coffee, capturedAt: at, source: "apple_wallet")
    XCTAssertEqual(store().take(userId: "u1").captures.count, 1)
  }

  func testAPaymentWithNoSessionGoesToTheNextSignIn() {
    let queue = store()
    _ = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    XCTAssertEqual(queue.take(userId: "u1").captures.count, 0)
    queue.adopt(userId: "u1", from: nil)
    XCTAssertEqual(queue.take(userId: "u1").captures.count, 1)
    XCTAssertFalse(queue.isEmpty(userId: "u1"))
  }

  func testAdoptKeepsOwnTakesFromAndDropsAnotherAccounts() {
    let queue = store()
    queue.adopt(userId: "guest", from: nil)
    let guests = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    queue.adopt(userId: "u1", from: "guest")
    let own = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    queue.adopt(userId: "u1", from: nil)
    let keys = queue.take(userId: "u1").captures.compactMap { $0["key"] as? String }
    XCTAssertEqual(keys, [guests, own])
    queue.adopt(userId: "u2", from: nil)
    XCTAssertTrue(queue.isEmpty(userId: "u2"))
    XCTAssertTrue(queue.isEmpty(userId: "u1"))
  }

  func testConfirmsStayOnlyForTheSameOwnerOrTheOneTakenFrom() {
    let queue = store()
    queue.adopt(userId: "guest", from: nil)
    queue.addConfirm("tx1")
    queue.addConfirm("tx1")
    queue.adopt(userId: "guest", from: nil)
    XCTAssertEqual(queue.take(userId: "guest").confirms, ["tx1"])
    queue.adopt(userId: "u1", from: "guest")
    XCTAssertEqual(queue.take(userId: "u1").confirms, ["tx1"])
    queue.adopt(userId: "u2", from: nil)
    XCTAssertEqual(queue.take(userId: "u2").confirms, [])
  }

  func testAckRemovesSavedItemsAndAppliedConfirms() {
    let queue = store()
    queue.adopt(userId: "u1", from: nil)
    let saved = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    let kept = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    queue.addConfirm("tx1")
    queue.addConfirm("tx2")
    queue.ack(keys: [saved], confirms: ["tx1"])
    let taken = queue.take(userId: "u1")
    XCTAssertEqual(taken.captures.compactMap { $0["key"] as? String }, [kept])
    XCTAssertEqual(taken.confirms, ["tx2"])
  }

  func testAnItemIsDroppedOnItsEighthRefusalNotBefore() {
    let queue = store()
    queue.adopt(userId: "u1", from: nil)
    let key = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    for _ in 1..<CaptureQueueStore.maxRefusals {
      XCTAssertEqual(queue.refuse(keys: [key], limit: CaptureQueueStore.maxRefusals), [])
    }
    XCTAssertEqual(queue.refuse(keys: [key], limit: CaptureQueueStore.maxRefusals), [key])
    XCTAssertTrue(queue.isEmpty(userId: "u1"))
    XCTAssertEqual(CaptureQueueStore.maxRefusals, 8)
  }

  func testClearForgetsEverything() {
    let queue = store()
    queue.adopt(userId: "u1", from: nil)
    _ = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    queue.addConfirm("tx1")
    queue.clear()
    XCTAssertTrue(queue.isEmpty(userId: "u1"))
    XCTAssertEqual(queue.take(userId: "u1").confirms, [])
    XCTAssertNil(queue.owner)
  }

  func testTheFileIsKeptOutOfBackups() throws {
    let queue = store()
    _ = queue.add(coffee, capturedAt: at, source: "apple_wallet")
    let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
    #if os(iOS)
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      XCTAssertEqual(
        attributes[.protectionKey] as? FileProtectionType,
        .completeUntilFirstUserAuthentication)
    #endif
  }
}
