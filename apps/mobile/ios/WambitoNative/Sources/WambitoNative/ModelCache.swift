import Foundation

/// One speech model kept loaded for as long as the process lives, so a tap on the microphone never
/// waits for the model to load. It is loaded in the background ([warm], from `warmUp`), handed to a
/// recording ([acquire]) and freed by [drop] (memory pressure, the models deleted). Generic over the
/// model so it can be tested without the native library. Port of the Android `ModelCache`.
public final class ModelCache<Model: AnyObject> {
  private enum Outcome { case running, kept, failed, discarded }

  private final class Load {
    let key: String
    var outcome = Outcome.running
    init(key: String) { self.key = key }
  }

  private let open: (String) throws -> Model
  private let queue: DispatchQueue
  /// Guards the state below; loads broadcast on it when they end.
  private let condition = NSCondition()
  private var model: Model?
  private var key: String?
  private var loading: Load?

  public init(open: @escaping (String) throws -> Model, queue: DispatchQueue) {
    self.open = open
    self.queue = queue
  }

  /// `"<path>#<language>"`.
  public static func key(path: String, language: String) -> String {
    "\(path)#\(language)"
  }

  /// The key of the model that is loaded now, or nil.
  public func loadedKey() -> String? {
    condition.lock()
    defer { condition.unlock() }
    return model == nil ? nil : key
  }

  /// Loads the model for [key] on the queue, unless it is loaded (or loading) already. [done] gets
  /// true once it is loaded, false when it failed or was dropped or replaced meanwhile.
  public func warm(_ key: String, done: @escaping (Bool) -> Void) {
    condition.lock()
    if model != nil && self.key == key {
      condition.unlock()
      done(true)
      return
    }
    let load = startLoad(key)
    condition.unlock()
    queue.async { [self] in
      condition.lock()
      while load.outcome == .running { condition.wait() }
      let kept = load.outcome == .kept
      condition.unlock()
      done(kept)
    }
  }

  /// The model for [key], loading it first if it is not (waiting for a load already running).
  /// Blocks: call it from a background queue. Nil when the model cannot be opened.
  public func acquire(_ key: String) -> Model? {
    condition.lock()
    defer { condition.unlock() }
    while true {
      if let model, self.key == key { return model }
      let load = startLoad(key)
      while load.outcome == .running { condition.wait() }
      if load.outcome == .failed { return nil }
    }
  }

  /// Forgets the model; a later [acquire] loads it again. A load running now is thrown away.
  public func drop() {
    condition.lock()
    model = nil
    key = nil
    if let load = loading {
      load.outcome = .discarded
      loading = nil
    }
    condition.broadcast()
    condition.unlock()
  }

  /// Under [condition]'s lock.
  private func startLoad(_ key: String) -> Load {
    if let loading, loading.key == key, loading.outcome == .running { return loading }
    // A load of another key still running is superseded: its model is thrown away.
    loading?.outcome = .discarded
    let load = Load(key: key)
    loading = load
    queue.async { [self] in
      let opened: Model?
      do { opened = try open(key) } catch { opened = nil }
      condition.lock()
      if load.outcome == .running {
        if let opened {
          model = opened
          self.key = key
          load.outcome = .kept
        } else {
          load.outcome = .failed
        }
        if loading === load { loading = nil }
      }
      condition.broadcast()
      condition.unlock()
    }
    return load
  }
}
