import AVFoundation
import Flutter
import UIKit

/// The feedback sounds (lib/feedback/feedback_platform.dart), on the `wambito/sounds` method channel.
/// Same methods and answers as the Android side (SoundChannel.kt): `preload({assets})` answers how
/// many assets loaded; `play({asset})` answers whether it played, and a `bad-sound` error without
/// an `asset`. One cached `AVAudioPlayer` per asset. The audio session is `.ambient`: the silent
/// switch mutes the sounds and music from another app keeps playing.
final class SoundChannel {
  /// The web's `VOLUME`.
  private static let volume: Float = 0.6

  private let channel: FlutterMethodChannel
  private var players: [String: AVAudioPlayer] = [:]
  private var sessionReady = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/sounds", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "preload":
        let args = call.arguments as? [String: Any]
        let assets = (args?["assets"] as? [Any] ?? []).compactMap { $0 as? String }
        result(assets.filter { self.player(for: $0) != nil }.count)
      case "play":
        guard let args = call.arguments as? [String: Any], let asset = args["asset"] as? String
        else {
          result(FlutterError(code: "bad-sound", message: "No asset", details: nil))
          return
        }
        result(self.play(asset))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func play(_ asset: String) -> Bool {
    guard let player = player(for: asset) else { return false }
    // A sound asked for while it is still playing starts over.
    player.currentTime = 0
    return player.play()
  }

  /// The cached player for a Flutter asset, loading it on first use; nil when the file is missing
  /// or unreadable (that sound stays silent).
  private func player(for asset: String) -> AVAudioPlayer? {
    if let cached = players[asset] { return cached }
    configureSession()
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil),
      let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    else { return nil }
    player.volume = SoundChannel.volume
    player.prepareToPlay()
    players[asset] = player
    return player
  }

  /// `.ambient`, set once: it follows the silent switch and mixes with other audio.
  private func configureSession() {
    guard !sessionReady else { return }
    try? AVAudioSession.sharedInstance().setCategory(.ambient)
    sessionReady = true
  }
}
