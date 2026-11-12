import Foundation
import XCTest

@testable import WambitoNative

final class VoiceAudioTests: XCTestCase {
  func testSilenceIsZero() { XCTAssertEqual(AudioLevel.of([0, 0, 0][...]), 0) }

  func testFullScaleIsOne() { XCTAssertEqual(AudioLevel.of([1, -1, 1, -1][...]), 1, accuracy: 1e-9) }

  func testFloorIsMinus50() {
    XCTAssertEqual(
      AudioLevel.of(Array(repeating: Float(pow(10, -50.0 / 20)), count: 640)[...]), 0, accuracy: 1e-6)
    XCTAssertEqual(
      AudioLevel.of(Array(repeating: Float(pow(10, -25.0 / 20)), count: 640)[...]), 0.5,
      accuracy: 1e-3)
  }

  func testEmptyIsZero() { XCTAssertEqual(AudioLevel.of([][...]), 0) }

  func testBufferCapsAt30s() {
    var b = PcmBuffer()
    let chunk = Array(repeating: Float(0.1), count: 640)
    for _ in 0..<750 { XCTAssertTrue(b.append(chunk[...])) }  // 750 x 640 = 480 000
    XCTAssertFalse(b.append(chunk[...]))
    XCTAssertEqual(b.samples.count, 480_000)
  }

  func testBufferKeepsExactlyUpToTheCap() {
    var b = PcmBuffer()
    XCTAssertTrue(b.append(Array(repeating: Float(0.1), count: 479_000)[...]))
    XCTAssertFalse(b.append(Array(repeating: Float(0.1), count: 2_000)[...]))
    XCTAssertEqual(b.samples.count, 480_000)
  }
}
