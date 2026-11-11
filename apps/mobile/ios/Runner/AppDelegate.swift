import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // One object per channel, kept here so the channel lives as long as the app.
  private var deviceChannel: DeviceChannel?
  private var hapticsChannel: HapticsChannel?
  private var soundChannel: SoundChannel?
  private var launchChannel: LaunchChannel?
  private var filesChannel: FilesChannel?
  private var passkeyChannel: PasskeyChannel?
  // Flutter keeps scene delegates weakly: held here for the life of the app.
  private var launchScenes: LaunchSceneHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerChannels(messenger: engineBridge.applicationRegistrar.messenger())
    // The app runs on a scene: its `wambito://` links arrive there, before Flutter's router.
    if let launchChannel {
      let scenes = LaunchSceneHandler(launch: launchChannel)
      launchScenes = scenes
      engineBridge.pluginRegistry.registrar(forPlugin: "WambitoLaunch")?.addSceneDelegate(scenes)
    }
  }

  /// Every `wambito/*` channel registers here: create its object, keep it in a property above.
  private func registerChannels(messenger: FlutterBinaryMessenger) {
    deviceChannel = DeviceChannel(messenger: messenger)
    hapticsChannel = HapticsChannel(messenger: messenger)
    soundChannel = SoundChannel(messenger: messenger)
    launchChannel = LaunchChannel(messenger: messenger)
    filesChannel = FilesChannel(messenger: messenger)
    passkeyChannel = PasskeyChannel(messenger: messenger)
  }

  /// A `wambito://` URL is the app's own: kept for Dart, never handed to Flutter's router (as on
  /// Android). Any other URL (the sign-in email's `https://app.wambito.com/auth/verify`) goes to Flutter.
  override func application(
    _ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if launchChannel?.handles(url) == true { return true }
    return super.application(app, open: url, options: options)
  }
}
