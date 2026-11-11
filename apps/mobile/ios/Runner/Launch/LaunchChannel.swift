import Flutter
import UIKit
import WambitoNative

/// The `wambito/launch` channel: Dart asks for the link the app was opened with (`take`) and is told
/// (`linkArrived`, no arguments) when one comes in while it runs. Same as the Android side
/// (MainActivity.kt); the links are the app's own (LaunchLinks.swift).
final class LaunchChannel {
  let pending = PendingLink()
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/launch", binaryMessenger: messenger)
    channel.setMethodCallHandler { [pending] call, result in
      switch call.method {
      case "take":
        result(pending.take())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // Only now is there a Dart side to tell; a link kept before this waits for `take`.
    pending.onKept = { [channel] in channel.invokeMethod("linkArrived", arguments: nil) }
  }

  /// Handles a URL the phone opened the app with. A `wambito://` URL is the app's own: kept (or, when
  /// it is not one of the links, dropped) and never handed to Flutter's router. True when it was one.
  func handles(_ url: URL) -> Bool {
    guard url.scheme == "wambito" else { return false }
    pending.keep(url)
    return true
  }
}

/// The app uses a scene (UIScene), so the phone delivers URLs here, not to the AppDelegate: a
/// plugin-style scene delegate that claims the `wambito://` ones before Flutter's deep linking sees
/// them. Cold start (`willConnectTo`) and a link while running (`openURLContexts`).
final class LaunchSceneHandler: NSObject, FlutterSceneLifeCycleDelegate {
  private let launch: LaunchChannel

  init(launch: LaunchChannel) { self.launch = launch }

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    handle(connectionOptions?.urlContexts ?? [])
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    handle(URLContexts)
  }

  private func handle(_ contexts: Set<UIOpenURLContext>) -> Bool {
    // `handles` is on the left of `||`, so it runs for every URL; `handled || handles(...)` would stop
    // at the first one that was handled and leave the rest unkept.
    contexts.reduce(false) { handled, context in launch.handles(context.url) || handled }
  }
}
