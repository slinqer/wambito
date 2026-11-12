import Flutter
import UIKit
import UserNotifications
import WambitoNative

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // One object per channel, kept here so the channel lives as long as the app.
  private var deviceChannel: DeviceChannel?
  private var hapticsChannel: HapticsChannel?
  private var soundChannel: SoundChannel?
  private var launchChannel: LaunchChannel?
  private var filesChannel: FilesChannel?
  private var passkeyChannel: PasskeyChannel?
  private var noticesChannel: NoticesChannel?
  // Flutter keeps scene delegates weakly: held here for the life of the app.
  private var launchScenes: LaunchSceneHandler?
  // The notification centre keeps its delegate weakly too.
  private var noticeTaps: NoticeTaps?
  /// A notice tapped before the launch channel exists (a cold start), handed to it once it does.
  private var tappedBeforeChannel: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Both before the launch ends: a tap that started the app arrives right after it, and the
    // system only runs background tasks registered by then.
    let taps = NoticeTaps { [weak self] url in self?.openNotice(url) }
    noticeTaps = taps
    UNUserNotificationCenter.current().delegate = taps
    DueTask.register()
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
    noticesChannel = NoticesChannel(messenger: messenger)
    if let url = tappedBeforeChannel, let launchChannel {
      tappedBeforeChannel = nil
      _ = launchChannel.handles(url)
    }
  }

  /// A tapped notice's link goes where a `wambito://` link does: kept for Dart, announced if it runs.
  private func openNotice(_ url: URL) {
    if let launchChannel {
      _ = launchChannel.handles(url)
    } else {
      tappedBeforeChannel = url
    }
  }

  /// A `wambito://` URL is the app's own: kept for Dart, never handed to Flutter's router (as on
  /// Android). Any other URL (the sign-in email's `https://app.wambito.com/auth/verify`) goes to Flutter.
  // Under UIScene iOS sends URLs to the scene (LaunchSceneHandler); this is a fallback only.
  override func application(
    _ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if launchChannel?.handles(url) == true { return true }
    return super.application(app, open: url, options: options)
  }
}

/// The two notices' taps and their showing while the app is open. A tap opens the notice's link
/// (`userInfo["link"]`: `due` -> `wambito://due`, `progress` -> `wambito://progress`), as the
/// notice's tap intent does on Android; with the app in front the notice still shows, as there.
final class NoticeTaps: NSObject, UNUserNotificationCenterDelegate {
  private let open: (URL) -> Void

  init(open: @escaping (URL) -> Void) { self.open = open }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let url = LaunchLinks.noticeTap(response.notification.request.content.userInfo)
    DispatchQueue.main.async { [open] in
      if let url { open(url) }
      completionHandler()
    }
  }
}
