import Flutter
import UIKit
import UniformTypeIdentifiers
import WambitoNative

/// Files in and out of the app, on the `wambito/files` method channel (lib/files/files_channel.dart),
/// as on Android (FilesChannel.kt): the system document picker for a file in (`pick`) and out
/// (`save`), the share sheet for handing one to another app (`share`). The app sees only the one
/// document the person chose.
///
///  * `pick({mimeTypes, maxBytes})` -> `{name, bytes}`, or nil when the picker was closed. Failures:
///    `busy`, `too-large` (details: the size when known), `unreadable`, `unavailable`.
///  * `save({name, bytes, mime})` -> true when saved, false when the picker was closed. Failures:
///    `busy`, `bad-arguments`, `write-failed`, `unavailable`.
///  * `share({name, bytes, mime})` -> true once the share sheet is up. Failures: `bad-arguments`,
///    `write-failed`, `unavailable`.
///  * `clearShared()` -> nil once every copy made for the share sheet is deleted.
///
/// One pick or save is under way at a time (`Busy`); every path that began one ends it and answers
/// the call exactly once.
final class FilesChannel: NSObject {
  private let channel: FlutterMethodChannel
  private let busy = Busy()
  /// Kept while a picker is up: the picker holds its delegate weakly.
  private var session: PickerSession?

  private static var sharedFolder: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("shared", isDirectory: true)
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/files", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "pick": self.pick(call, result)
      case "save": self.save(call, result)
      case "share": self.share(call, result)
      case "clearShared":
        // Deleting the account: the copies made for the share sheet go now.
        DispatchQueue.global(qos: .utility).async {
          Self.clearShared()
          DispatchQueue.main.async { result(nil) }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
    // Copies left by an earlier run (a share whose app was killed before the next one).
    DispatchQueue.global(qos: .utility).async { Self.clearShared() }
  }

  private static func clearShared() {
    try? FileManager.default.removeItem(at: sharedFolder)
  }

  /// The view controller on top of the active window of the active scene.
  private func presenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var top = window?.rootViewController
    while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
    return top
  }

  private func pick(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard busy.begin() else {
      return result(FlutterError(code: "busy", message: "A file is already being picked", details: nil))
    }
    guard let presenter = presenter() else {
      busy.end()
      return result(FlutterError(code: "unavailable", message: "Nothing to show the picker on", details: nil))
    }
    let args = call.arguments as? [String: Any]
    let limit = FileTransfer.limitOf(args?["maxBytes"])
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.commaSeparatedText, .plainText], asCopy: true)
    picker.allowsMultipleSelection = false
    let session = PickerSession(
      onPicked: { [weak self] urls in self?.read(urls.first, limit: limit, result) },
      onCancelled: { [weak self] in
        self?.finish()
        result(nil)
      })
    self.session = session
    picker.delegate = session
    presenter.present(picker, animated: true)
  }

  /// Ends the pick or save: the slot is free and the picker's delegate is let go.
  private func finish() {
    session = nil
    busy.end()
  }

  /// Reads the picked copy off the main thread, within the limit, then deletes it.
  private func read(_ url: URL?, limit: Int, _ result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      var answer: Any?
      if let url {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let size, size > limit {
          answer = FlutterError(
            code: "too-large", message: "The file is larger than \(limit) bytes", details: size)
        } else if let data = FileTransfer.readBounded(url, limit: limit) {
          answer = ["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: data)]
        } else if FileManager.default.fileExists(atPath: url.path),
          (try? FileHandle(forReadingFrom: url)) != nil
        {
          // Readable, yet past the limit: no size was announced, or it lied.
          answer = FlutterError(
            code: "too-large", message: "The file is larger than \(limit) bytes", details: nil)
        } else {
          answer = FlutterError(code: "unreadable", message: "The file could not be opened", details: nil)
        }
        try? FileManager.default.removeItem(at: url)
      } else {
        answer = FlutterError(code: "unreadable", message: "The file could not be opened", details: nil)
      }
      DispatchQueue.main.async {
        self?.finish()
        result(answer)
      }
    }
  }

  private func save(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard busy.begin() else {
      return result(FlutterError(code: "busy", message: "A file is already being saved", details: nil))
    }
    let args = call.arguments as? [String: Any]
    guard let bytes = (args?["bytes"] as? FlutterStandardTypedData)?.data, let name = args?["name"] as? String
    else {
      busy.end()
      return result(FlutterError(code: "bad-arguments", message: "A name and bytes are needed", details: nil))
    }
    guard let presenter = presenter() else {
      busy.end()
      return result(FlutterError(code: "unavailable", message: "Nothing to show the picker on", details: nil))
    }
    // A folder of its own, so the file keeps the person's name without clashing with another.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = folder.appendingPathComponent(FileTransfer.safeName(name))
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try bytes.write(to: file)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      busy.end()
      return result(FlutterError(code: "write-failed", message: error.localizedDescription, details: nil))
    }
    let picker = UIDocumentPickerViewController(forExporting: [file])
    let cleanUp = { try? FileManager.default.removeItem(at: folder) }
    let session = PickerSession(
      onPicked: { [weak self] _ in
        cleanUp()
        self?.finish()
        result(true)
      },
      onCancelled: { [weak self] in
        cleanUp()
        self?.finish()
        result(false)
      })
    self.session = session
    picker.delegate = session
    presenter.present(picker, animated: true)
  }

  private func share(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    guard let bytes = (args?["bytes"] as? FlutterStandardTypedData)?.data, let name = args?["name"] as? String
    else {
      return result(FlutterError(code: "bad-arguments", message: "A name and bytes are needed", details: nil))
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let file = Self.sharedFolder.appendingPathComponent(FileTransfer.safeName(name))
      do {
        // Earlier shares are done with: the receiving app has had the whole time since to read them.
        Self.clearShared()
        try FileManager.default.createDirectory(at: Self.sharedFolder, withIntermediateDirectories: true)
        try bytes.write(to: file)
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "write-failed", message: error.localizedDescription, details: nil))
        }
        return
      }
      DispatchQueue.main.async {
        guard let self, let presenter = self.presenter() else {
          result(FlutterError(code: "unavailable", message: "Nothing to show the share sheet on", details: nil))
          return
        }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
          // iPad: a popover must be anchored; the centre of the screen's root view.
          let root = presenter.view!
          popover.sourceView = root
          popover.sourceRect = CGRect(x: root.bounds.midX, y: root.bounds.midY, width: 0, height: 0)
          popover.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: true) { result(true) }
      }
    }
  }
}

/// A document picker's delegate: answers once, either with the chosen URLs or with the cancel.
private final class PickerSession: NSObject, UIDocumentPickerDelegate {
  private let onPicked: ([URL]) -> Void
  private let onCancelled: () -> Void

  init(onPicked: @escaping ([URL]) -> Void, onCancelled: @escaping () -> Void) {
    self.onPicked = onPicked
    self.onCancelled = onCancelled
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    onPicked(urls)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    onCancelled()
  }
}
