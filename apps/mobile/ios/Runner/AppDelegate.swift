import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // One object per channel, kept here so the channel lives as long as the app.
  private var deviceChannel: DeviceChannel?
  private var hapticsChannel: HapticsChannel?
  private var soundChannel: SoundChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerChannels(messenger: engineBridge.applicationRegistrar.messenger())
  }

  /// Every `wambito/*` channel registers here: create its object, keep it in a property above.
  private func registerChannels(messenger: FlutterBinaryMessenger) {
    deviceChannel = DeviceChannel(messenger: messenger)
    hapticsChannel = HapticsChannel(messenger: messenger)
    soundChannel = SoundChannel(messenger: messenger)
  }
}
