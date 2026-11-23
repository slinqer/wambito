import AppIntents
import Foundation
import WambitoNative

/// "Anotar pago de Wallet": the Shortcuts action the Transaction automation calls on every Apple Pay
/// payment (spec 2026-11-22-ios-wallet-capture-design.md, section 3.1). It runs without opening the
/// app: the payment is queued and saved by `captureMain` (CaptureRun), never thrown back at the
/// person as an error.
///
/// Persistent names: the type name and the parameters `amount`, `merchant`, `card` (automations point
/// at them; renaming breaks every one silently).
@available(iOS 17, *)
struct LogWalletPaymentIntent: AppIntent {
  static let title = LocalizedStringResource("wallet.intent.title", table: "AppIntents")
  static let description = IntentDescription(
    LocalizedStringResource("wallet.intent.description", table: "AppIntents"))
  static let openAppWhenRun = false
  static let isDiscoverable = true

  @Parameter(title: LocalizedStringResource("wallet.intent.amount", table: "AppIntents"))
  var amount: IntentCurrencyAmount

  @Parameter(title: LocalizedStringResource("wallet.intent.merchant", table: "AppIntents"))
  var merchant: String

  /// Only for the person's eyes in Shortcuts: never stored.
  @Parameter(title: LocalizedStringResource("wallet.intent.card", table: "AppIntents"))
  var card: String?

  func perform() async throws -> some IntentResult {
    // A forgotten automation stores nothing once the switch is off.
    guard CaptureSettings.walletOn() else { return .result() }
    guard
      let payment = WalletPayment.read(
        amount: amount.amount, currencyCode: amount.currencyCode, merchant: merchant)
    else { return .result() }
    let store = CaptureQueueStore.standard()
    _ = store.add(payment, capturedAt: Date(), source: CaptureSettings.wallet)
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      CaptureRun.send(store: store) { _ in done.resume() }
    }
    return .result()
  }
}

/// Puts the action in Shortcuts as soon as the app is installed: nothing to add by hand.
@available(iOS 17, *)
struct WambitoShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogWalletPaymentIntent(),
      phrases: ["\(.applicationName) wallet"],
      shortTitle: LocalizedStringResource("wallet.intent.title", table: "AppIntents"),
      systemImageName: "creditcard"
    )
  }
}
