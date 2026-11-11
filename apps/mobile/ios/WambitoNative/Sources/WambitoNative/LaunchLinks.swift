import Foundation

/// The app's own links: `wambito://add` opens the add sheet, `capture` quick capture, `due` home with
/// the payments due today, `progress` "Guarda tu progreso", `home` home, and `review/<id>` a detected
/// transaction's review. Same rules as `LaunchLinks.kt` on Android.
public enum LaunchLinks {
  static let scheme = "wambito"
  private static let hosts: Set<String> = ["add", "capture", "due", "progress", "home", "review"]

  /// The link [url] is, or nil when it is not one of the app's links. Anything else (another scheme,
  /// another host, a path where none belongs) is refused.
  public static func linkOf(_ url: URL) -> String? {
    guard url.scheme == scheme, let host = url.host, hosts.contains(host) else { return nil }
    if host == "review" {
      // Exactly one segment: the transaction's id.
      let segments = url.path.split(separator: "/", omittingEmptySubsequences: false)
        .dropFirst()  // the empty piece before the leading slash
      guard url.path.hasPrefix("/"), segments.count == 1, segments[segments.startIndex] != "" else {
        return nil
      }
    } else if !url.path.isEmpty && url.path != "/" {
      return nil
    }
    return url.absoluteString
  }
}

/// The link the app was opened with, kept until Dart takes it (`lib/launch/launch_links.dart`).
/// A link that comes before Dart listens is not lost; one that comes while it listens is announced
/// through `onKept`. Used from the main thread.
public final class PendingLink {
  private var link: String?

  /// Called once per kept link.
  public var onKept: (() -> Void)?

  public init() {}

  /// Keeps [url] when it is one of the app's links; true when it did.
  @discardableResult
  public func keep(_ url: URL) -> Bool {
    guard let kept = LaunchLinks.linkOf(url) else { return false }
    link = kept
    onKept?()
    return true
  }

  /// The kept link, once: the next call answers nil.
  public func take() -> String? {
    defer { link = nil }
    return link
  }
}
