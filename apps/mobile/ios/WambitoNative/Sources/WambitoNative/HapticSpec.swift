import Foundation

/// One step of a composition: `click`, `tick`, `thud` or `lowTick` at a `scale` (0 to 1) after
/// `delayMs` of quiet. Same data as the Android side (HapticSpec.kt).
public struct PrimitiveStep: Equatable {
    public let name: String
    public let scale: Double
    public let delayMs: Int

    public init(name: String, scale: Double, delayMs: Int) {
        self.name = name
        self.scale = scale
        self.delayMs = delayMs
    }

    /// What Android plays in its place on a motor without it; kept for parity with the Kotlin side.
    public var fallback: String? {
        switch name {
        case "thud": return "click"
        case "lowTick": return "tick"
        default: return nil
        }
    }
}

/// How hard a tap is: the impact generator styles iOS offers.
public enum HapticStyle: Equatable {
    case light, medium, heavy, rigid, soft
}

/// One tap to play: after `delayMs` from the start, a `style` impact at `intensity` (0 to 1).
public struct HapticStep: Equatable {
    public let delayMs: Int
    public let style: HapticStyle
    public let intensity: Double

    public init(delayMs: Int, style: HapticStyle, intensity: Double) {
        self.delayMs = delayMs
        self.style = style
        self.intensity = intensity
    }
}

/// What Dart asks the motor for (lib/feedback/feedback_event.dart's `HapticPattern`): the web's
/// pattern as `waveform` (ms: vibrate, pause, vibrate...) and the same feel as `primitives`.
/// Plain data, so it is tested without a phone.
public struct HapticSpec: Equatable {
    public let waveform: [Int]
    public let primitives: [PrimitiveStep]

    public init(waveform: [Int], primitives: [PrimitiveStep]) {
        self.waveform = waveform
        self.primitives = primitives
    }

    private static let maxSteps = 32
    private static let maxMs = 1000
    private static let known: Set<String> = ["click", "tick", "thud", "lowTick"]

    /// The spec in a method call's arguments, or nil when there is nothing sound to play.
    public static func parse(_ arguments: Any?) -> HapticSpec? {
        guard let map = arguments as? [String: Any],
            let raw = map["waveform"] as? [Any],
            !raw.isEmpty, raw.count <= maxSteps
        else { return nil }
        var waveform: [Int] = []
        for item in raw {
            guard let number = item as? NSNumber else { return nil }
            let value = number.intValue
            if value < 0 || value > maxMs { return nil }
            waveform.append(value)
        }
        return HapticSpec(waveform: waveform, primitives: primitives(map["primitives"]))
    }

    // A step it cannot read drops the whole composition: the waveform still plays.
    private static func primitives(_ raw: Any?) -> [PrimitiveStep] {
        guard let steps = raw as? [Any], steps.count <= maxSteps else { return [] }
        var result: [PrimitiveStep] = []
        for step in steps {
            guard let entry = step as? [String: Any],
                let name = entry["name"] as? String, known.contains(name),
                let scale = entry["scale"] as? NSNumber,
                let delay = entry["delay"] as? NSNumber
            else { return [] }
            result.append(
                PrimitiveStep(
                    name: name,
                    scale: min(max(scale.doubleValue, 0), 1),
                    delayMs: max(delay.intValue, 0)))
        }
        return result
    }

    /// The taps to play: the primitives when there are any, else one medium tap for each "on" span
    /// of the waveform (Android plays `[0] + waveform` as off/on pairs, so indexes 0, 2, 4...).
    public func steps() -> [HapticStep] {
        if !primitives.isEmpty {
            return primitives.map {
                HapticStep(delayMs: $0.delayMs, style: Self.style(of: $0.name), intensity: $0.scale)
            }
        }
        var result: [HapticStep] = []
        var elapsed = 0
        for (index, span) in waveform.enumerated() {
            if index % 2 == 0 {
                result.append(HapticStep(delayMs: elapsed, style: .medium, intensity: 1))
            }
            elapsed += span
        }
        return result
    }

    private static func style(of name: String) -> HapticStyle {
        switch name {
        case "click": return .rigid
        case "thud": return .heavy
        case "lowTick": return .soft
        default: return .light
        }
    }
}
