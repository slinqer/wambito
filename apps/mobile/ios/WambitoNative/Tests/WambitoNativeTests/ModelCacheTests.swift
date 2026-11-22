import XCTest
@testable import WambitoNative

private final class Box {}

private struct OpenFailure: Error {}

private final class Opener {
  private let lock = NSLock()
  private var opened = 0
  private var failuresLeft: Int
  private let delay: TimeInterval

  init(delay: TimeInterval = 0, failures: Int = 0) {
    self.delay = delay
    self.failuresLeft = failures
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return opened
  }

  func open(_ key: String) throws -> Box {
    lock.lock()
    opened += 1
    let fail = failuresLeft > 0
    if fail { failuresLeft -= 1 }
    lock.unlock()
    if delay > 0 { Thread.sleep(forTimeInterval: delay) }
    if fail { throw OpenFailure() }
    return Box()
  }
}

final class ModelCacheTests: XCTestCase {
  private func cache(_ opener: Opener) -> ModelCache<Box> {
    ModelCache(open: opener.open, queue: DispatchQueue(label: "test.model-cache"))
  }

  func testWarmLoadsOnceForTheSameKey() {
    let opener = Opener()
    let cache = cache(opener)
    let first = expectation(description: "first")
    let second = expectation(description: "second")
    cache.warm("a#es") { XCTAssertTrue($0); first.fulfill() }
    cache.warm("a#es") { XCTAssertTrue($0); second.fulfill() }
    wait(for: [first, second], timeout: 5)
    XCTAssertEqual(opener.count, 1)
    XCTAssertEqual(cache.loadedKey(), "a#es")
  }

  func testAcquireWaitsForTheWarm() {
    let opener = Opener(delay: 0.2)
    let cache = cache(opener)
    cache.warm("a#es") { _ in }
    let model = cache.acquire("a#es")
    XCTAssertNotNil(model)
    XCTAssertTrue(model === cache.acquire("a#es"))
    XCTAssertEqual(opener.count, 1)
  }

  func testOtherKeyReplaces() {
    let opener = Opener()
    let cache = cache(opener)
    XCTAssertNotNil(cache.acquire("a#es"))
    XCTAssertNotNil(cache.acquire("b#pt"))
    XCTAssertEqual(cache.loadedKey(), "b#pt")
    XCTAssertEqual(opener.count, 2)
  }

  func testOpenFailureIsNilAndNotCached() {
    let opener = Opener(failures: 1)
    let cache = cache(opener)
    XCTAssertNil(cache.acquire("a#es"))
    XCTAssertNil(cache.loadedKey())
    XCTAssertNotNil(cache.acquire("a#es"))
    XCTAssertEqual(opener.count, 2)
  }

  func testWarmReportsFailure() {
    let cache = cache(Opener(failures: 1))
    let done = expectation(description: "done")
    cache.warm("a#es") { XCTAssertFalse($0); done.fulfill() }
    wait(for: [done], timeout: 5)
    XCTAssertNil(cache.loadedKey())
  }

  func testDropForgets() {
    let opener = Opener()
    let cache = cache(opener)
    XCTAssertNotNil(cache.acquire("a#es"))
    cache.drop()
    XCTAssertNil(cache.loadedKey())
    XCTAssertNotNil(cache.acquire("a#es"))
    XCTAssertEqual(opener.count, 2)
  }

  func testKeyFormat() {
    XCTAssertEqual(ModelCache<Box>.key(path: "/m/canary", language: "es"), "/m/canary#es")
  }

  func testCurrentIsTheLoadedModelWithoutLoading() {
    let opener = Opener()
    let cache = cache(opener)
    XCTAssertNil(cache.current("a#es"))
    XCTAssertEqual(opener.count, 0)
    let model = cache.acquire("a#es")
    XCTAssertTrue(cache.current("a#es") === model)
    XCTAssertNil(cache.current("b#es"))
    cache.drop()
    XCTAssertNil(cache.current("a#es"))
  }
}
