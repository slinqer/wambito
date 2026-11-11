import Foundation
import UniformTypeIdentifiers

/// The document picker's types, from the MIME list the Dart side asks for (csvMimeTypes).
public enum PickerTypes {
    /// The picker's types for the `mimeTypes` argument: each known MIME type once, in order;
    /// `application/octet-stream` is any data; unknown ones (the system makes up a dynamic type for them) are dropped. When none maps (or none was
    /// given) CSV and plain text.
    public static func contentTypes(_ argument: Any?) -> [UTType] {
        var types: [UTType] = []
        for case let mime as String in (argument as? [Any]) ?? [] {
            let type = mime == "application/octet-stream" ? UTType.data : UTType(mimeType: mime)
            if let type, !type.isDynamic, !types.contains(type) { types.append(type) }
        }
        return types.isEmpty ? [.commaSeparatedText, .plainText] : types
    }
}

/// Runs a block the first time only: a picker's answer is given once, whichever way it ends (a pick,
/// the cancel button, a swipe down, a refused present).
public final class AnswerOnce {
    private let lock = NSLock()
    private var done = false

    public init() {}

    /// True when this call ran the block.
    @discardableResult
    public func run(_ block: () -> Void) -> Bool {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { block() }
        return first
    }
}
