import CoreHaptics
import Flutter
import UIKit
import WambitoNative

/// The phone's motor (lib/feedback/feedback_platform.dart), on the `wambito/haptics` method channel.
/// Same method and answers as the Android side (HapticsChannel.kt): `vibrate({waveform, primitives})`
/// answers true when the phone has a haptics engine and was asked to play, false otherwise, and a
/// `bad-pattern` error when there is nothing sound to play.
final class HapticsChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/haptics", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "vibrate":
        guard let spec = HapticSpec.parse(call.arguments) else {
          result(FlutterError(code: "bad-pattern", message: "Nothing sound to play", details: nil))
          return
        }
        result(HapticsChannel.play(spec))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Whether the phone has a haptics engine and was asked to play.
  private static func play(_ spec: HapticSpec) -> Bool {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
    for step in spec.steps() {
      let tap = {
        let generator = UIImpactFeedbackGenerator(style: feedbackStyle(step.style))
        generator.impactOccurred(intensity: CGFloat(step.intensity))
      }
      if step.delayMs == 0 {
        tap()
      } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(step.delayMs), execute: tap)
      }
    }
    return true
  }

  private static func feedbackStyle(_ style: HapticStyle) -> UIImpactFeedbackGenerator.FeedbackStyle {
    switch style {
    case .light: return .light
    case .medium: return .medium
    case .heavy: return .heavy
    case .rigid: return .rigid
    case .soft: return .soft
    }
  }
}
