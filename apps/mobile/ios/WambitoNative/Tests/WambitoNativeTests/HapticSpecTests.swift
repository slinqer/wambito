import XCTest
@testable import WambitoNative

final class HapticSpecTests: XCTestCase {
    private func args(_ waveform: Any?, primitives: Any? = nil) -> [String: Any] {
        var map: [String: Any] = [:]
        if let waveform { map["waveform"] = waveform }
        if let primitives { map["primitives"] = primitives }
        return map
    }

    func testRejectsMissingOrNonMapArguments() {
        XCTAssertNil(HapticSpec.parse(nil))
        XCTAssertNil(HapticSpec.parse("x"))
        XCTAssertNil(HapticSpec.parse(args(nil)))
    }

    func testRejectsEmptyWaveform() {
        XCTAssertNil(HapticSpec.parse(args([Int]())))
    }

    func testRejectsMoreThan32Steps() {
        XCTAssertNotNil(HapticSpec.parse(args(Array(repeating: 10, count: 32))))
        XCTAssertNil(HapticSpec.parse(args(Array(repeating: 10, count: 33))))
    }

    func testRejectsNegativeOrTooLongValues() {
        XCTAssertNil(HapticSpec.parse(args([30, -1])))
        XCTAssertNil(HapticSpec.parse(args([30, 1001])))
        XCTAssertNotNil(HapticSpec.parse(args([0, 1000])))
    }

    func testRejectsNonNumbers() {
        XCTAssertNil(HapticSpec.parse(args([30, "x"])))
    }

    func testUnknownPrimitiveDropsAllPrimitivesButKeepsWaveform() {
        let spec = HapticSpec.parse(args([30], primitives: [
            ["name": "click", "scale": 0.5, "delay": 0],
            ["name": "buzz", "scale": 0.5, "delay": 0],
        ]))
        XCTAssertEqual(spec?.waveform, [30])
        XCTAssertEqual(spec?.primitives, [])
    }

    func testScaleClampsAndDelayIsNotNegative() {
        let spec = HapticSpec.parse(args([30], primitives: [
            ["name": "click", "scale": 2.0, "delay": -5],
            ["name": "tick", "scale": -1, "delay": 10],
        ]))
        XCTAssertEqual(spec?.primitives.map(\.scale), [1.0, 0.0])
        XCTAssertEqual(spec?.primitives.map(\.delayMs), [0, 10])
    }

    func testFallbacks() {
        XCTAssertEqual(PrimitiveStep(name: "thud", scale: 1, delayMs: 0).fallback, "click")
        XCTAssertEqual(PrimitiveStep(name: "lowTick", scale: 1, delayMs: 0).fallback, "tick")
        XCTAssertNil(PrimitiveStep(name: "click", scale: 1, delayMs: 0).fallback)
    }

    func testPrimitiveStepsMapToStyles() {
        let spec = HapticSpec(waveform: [30], primitives: [
            PrimitiveStep(name: "click", scale: 0.5, delayMs: 0),
            PrimitiveStep(name: "thud", scale: 1.0, delayMs: 40),
        ])
        XCTAssertEqual(spec.steps(), [
            HapticStep(delayMs: 0, style: .rigid, intensity: 0.5),
            HapticStep(delayMs: 40, style: .heavy, intensity: 1.0),
        ])
    }

    func testTickAndLowTickStyles() {
        let spec = HapticSpec(waveform: [30], primitives: [
            PrimitiveStep(name: "tick", scale: 0.3, delayMs: 0),
            PrimitiveStep(name: "lowTick", scale: 0.2, delayMs: 5),
        ])
        XCTAssertEqual(spec.steps().map(\.style), [.light, .soft])
    }

    func testWaveformStepsAreTheOnSpans() {
        let spec = HapticSpec(waveform: [30, 60, 30], primitives: [])
        XCTAssertEqual(spec.steps(), [
            HapticStep(delayMs: 0, style: .medium, intensity: 1),
            HapticStep(delayMs: 90, style: .medium, intensity: 1),
        ])
    }
}
