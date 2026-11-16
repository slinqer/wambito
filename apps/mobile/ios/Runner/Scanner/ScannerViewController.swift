import AVFoundation
import UIKit

/// The camera, full screen, for one QR (`ScannerChannel`): `AVCaptureMetadataOutput` set to `.qr`
/// (the system's own detector, no third-party code). The first text that starts with `wambito://pair?`
/// is the answer; any other QR is ignored, as the web's scanner ignores it. Its close button answers
/// cancelled; a session that cannot start answers failed. The session stops when the screen goes away.
final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  enum Outcome {
    case text(String)
    case cancelled
    case failed
  }

  /// The only QR the app wants: the pairing link (lib/local/pairing.dart).
  private static let pairPrefix = "wambito://pair?"

  private let onOutcome: (Outcome) -> Void
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "com.wambito.app.scanner")
  private var previewLayer: AVCaptureVideoPreviewLayer?
  /// The camera could not be set up: answered once the screen is up, so it can be dismissed.
  private var setupFailed = false
  /// The answer is given once, whichever way the screen ends.
  private var answered = false

  init(onOutcome: @escaping (Outcome) -> Void) {
    self.onOutcome = onOutcome
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  /// A word of the scanner's screen, from the same table as the notices (Notices.strings).
  private static func word(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: "Notices")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    let hint = UILabel()
    hint.text = Self.word("scanner_hint")
    hint.textColor = .white
    hint.numberOfLines = 0
    hint.textAlignment = .center
    hint.font = .preferredFont(forTextStyle: .body)
    hint.adjustsFontForContentSizeCategory = true
    hint.backgroundColor = UIColor.black.withAlphaComponent(0.6)
    hint.translatesAutoresizingMaskIntoConstraints = false

    var configuration = UIButton.Configuration.filled()
    configuration.title = Self.word("scanner_close")
    configuration.cornerStyle = .capsule
    let close = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
      self?.answer(.cancelled)
    })
    close.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(hint)
    view.addSubview(close)
    NSLayoutConstraint.activate([
      hint.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      hint.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hint.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      close.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      close.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
    ])

    setupFailed = !configureSession()
  }

  private func configureSession() -> Bool {
    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else { return false }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return false }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    guard output.availableMetadataObjectTypes.contains(.qr) else { return false }
    output.metadataObjectTypes = [.qr]

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer.insertSublayer(layer, at: 0)
    previewLayer = layer
    return true
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if setupFailed { return answer(.failed) }
    let session = session
    sessionQueue.async { if !session.isRunning { session.startRunning() } }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stop()
  }

  private func stop() {
    let session = session
    sessionQueue.async { if session.isRunning { session.stopRunning() } }
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
      if let text = code.stringValue, text.hasPrefix(Self.pairPrefix) {
        return answer(.text(text))
      }
    }
  }

  /// Answers once, stops the camera and closes the screen.
  private func answer(_ outcome: Outcome) {
    guard !answered else { return }
    answered = true
    stop()
    dismiss(animated: true) { [onOutcome] in onOutcome(outcome) }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // Swiped away by the system with no answer given: the call must not stay open.
    if !answered {
      answered = true
      onOutcome(.cancelled)
    }
  }
}
