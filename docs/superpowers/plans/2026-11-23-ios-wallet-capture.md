# iOS Wallet capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apple Pay payments reach Wambito on an iPhone with the app closed: a Shortcuts Transaction
automation calls Wambito's "Anotar pago de Wallet" action, which queues the payment and saves it
encrypted through the headless engine, then posts a silent "¿bien?" notification.

**Architecture:** Pure logic (amount, queue, money text) goes in the `WambitoNative` Swift package
with `swift test`; the Runner gets `ios/Runner/Capture/` (App Intent, the `wambito/capture` channel
for both engines, the run that calls `captureMain`, the notification). Dart reuses the Android path
(`captureMain`, `QueuedCapture`, `AutoCapturePlatform`) and adds the iOS rows and setup sheets to
Settings → Captura automática.

**Tech Stack:** Swift 5.9, AppIntents (iOS 17+), UserNotifications, Flutter/Dart with Riverpod.

**Spec:** `docs/superpowers/specs/2026-11-22-ios-wallet-capture-design.md` (decisions 1–8).

## Global Constraints

- iOS 17 and later: every AppIntents type is `@available(iOS 17, *)`; on iOS 16 `status` answers null.
- Encrypted accounts only; Swift never seals or writes the vault: only `captureMain` writes.
- Persistent names (never rename): `LogWalletPaymentIntent`, its parameters `amount`, `merchant`,
  `card`; queue `wambito.capture.queue`; notification category `wambito.capture`; source `apple_wallet`.
- Money is integer cents, never a float on the way (`Decimal` → cents).
- Copy in es, en, it, pt; app copy has no hard-coded words (`test/l10n/capture_copy_test.dart`).
- Every new Swift file added by hand to `ios/Runner.xcodeproj/project.pbxproj` (Runner is not a
  synchronized group).
- No Revolut, no location, no SMS/email (decisions 3, 7, 8).
- Commits: `feat(ios): …` style, staged by path, never a `Co-Authored-By` line.

## Review Focus

1. **Phone locked, first unlock done:** the queue file must be readable and writable
   (`.completeUntilFirstUserAuthentication`), or a locked payment is lost. Test in Task 2.
2. **Switch off but automation still installed:** `perform()` stores nothing. Test in Task 4.
3. **No session (signed out, never set up):** the payment is queued untagged… and Android drops
   untagged items on `adopt`. iOS must tag them with no owner and keep them for the next sign-in's
   `sendQueued` (spec 3.1 "handed over on the next sign-in"). Test in Task 2.
4. **Amount with more than two decimals or zero/negative** (refund passed by mistake): dropped
   quietly, never rounded into a charge. Test in Task 1.
5. **Two payments seconds apart while a run is going** (`HeadlessRunner` answers `busy`): the
   second stays queued and is sent by the next run, never lost. Test in Task 4.

---

### Task 1: Branch, and the amount reading

**Files:**
- Create: `apps/mobile/ios/WambitoNative/Sources/WambitoNative/WalletPayment.swift`
- Test: `apps/mobile/ios/WambitoNative/Tests/WambitoNativeTests/WalletPaymentTests.swift`

**Interfaces:**
- Produces: `public struct WalletPayment: Equatable { cents: Int64; currency: String; merchant: String }`
  and `public static func WalletPayment.read(amount: Decimal, currencyCode: String?, merchant: String?) -> WalletPayment?`

- [ ] **Step 1: Branch from the latest main and bring the spec**

```bash
git fetch origin
git switch -c feat/ios-wallet-capture origin/main
git cherry-pick 38f7531e            # the spec as first written
git checkout docs/ios-wallet-capture-spec -- docs/superpowers/specs/2026-11-22-ios-wallet-capture-design.md docs/superpowers/plans/2026-11-23-ios-wallet-capture.md
git add docs/superpowers/specs/2026-11-22-ios-wallet-capture-design.md docs/superpowers/plans/2026-11-23-ios-wallet-capture.md
git commit -m "docs: installable shortcut on ios 27 and the plan for wallet capture"
```

(If the spec edits were committed on `docs/ios-wallet-capture-spec` first, cherry-pick that commit instead.)

- [ ] **Step 2: Write the failing tests** — `WalletPaymentTests`:
  - `read(amount: 18000, "COP", "Juan Valdez")` → `cents 1_800_000, "COP", "Juan Valdez"`.
  - `read(amount: 12.5, "eur", " Mercadona  ")` → `1250, "EUR", "Mercadona"` (code uppercased, merchant trimmed).
  - `Decimal(string: "18000.005")` → nil (more than two decimals); `0` → nil; `-5` → nil.
  - currency nil, `""`, `"CO"`, `"PESOS"` → nil (exactly three letters).
  - merchant nil or `"   "` → nil.
  - an amount above `Int64.max / 100` → nil.
- [ ] **Step 3: Run** `cd apps/mobile/ios/WambitoNative && swift test --filter WalletPaymentTests` — Expected: FAIL (no `WalletPayment`).
- [ ] **Step 4: Implement `WalletPayment.read`** with `Decimal` arithmetic only (`NSDecimalNumber` multiply by 100, check it equals its own rounding with scale 0).
- [ ] **Step 5: Run** the same command — Expected: PASS.
- [ ] **Step 6: Commit** `feat(ios): read a wallet payment into cents`.

### Task 2: The capture queue

**Files:**
- Create: `apps/mobile/ios/WambitoNative/Sources/WambitoNative/CaptureQueueStore.swift`
- Test: `apps/mobile/ios/WambitoNative/Tests/WambitoNativeTests/CaptureQueueStoreTests.swift`

**Interfaces:**
- Consumes: `WalletPayment` (Task 1).
- Produces: `public final class CaptureQueueStore` (port of Android `CaptureQueue.kt`; same semantics
  unless noted):
  - `init(file: URL)`; `static func standard() -> CaptureQueueStore` = Application Support
    `wambito.capture.queue.json`, created with `FileProtectionType.completeUntilFirstUserAuthentication`
    and `BackupExclusion.exclude(path:)`.
  - `func add(_ p: WalletPayment, capturedAt: Date, source: String) -> String` (returns the new key; tags the current `owner`, nil if none).
  - `func take(userId: String) -> (captures: [[String: Any]], confirms: [String])` — items as `QueuedCapture.fromJson` reads them: `key, kind ("expense"), amount (Int cents), currency, merchant, capturedAt (ISO-8601 UTC with milliseconds), source`.
  - `func adopt(userId: String, from: String?)` — keeps `userId`'s, re-tags `from`'s, **and re-tags untagged items** (Review Focus 3; differs from Android on purpose: on iOS an untagged item is a payment made before any session); drops the rest; confirms kept only if owner unchanged or previous owner == `from`.
  - `func ack(keys: [String], confirms: [String])`, `func addConfirm(_ txId: String)`,
    `func refuse(keys: [String], limit: Int) -> [String]`, `func clear()`, `func isEmpty(userId: String) -> Bool`.
  - `public static let maxRefusals = 8`.
  - One serial lock; every write is an atomic file replace.

- [ ] **Step 1: Write the failing tests** — add/take round trip (JSON keys exactly as above, `amount` an Int); a second store on the same file sees the items (survives restart); `adopt` keeps own, re-tags `from` and untagged, drops a third user's; `ack` removes items and confirms; `refuse` drops a key on its 8th refusal and returns it, not before; `clear` empties everything; `standard()`'s file has `completeUntilFirstUserAuthentication` protection and `isExcludedFromBackup` (skip the protection assertion on macOS).
- [ ] **Step 2: Run** `swift test --filter CaptureQueueStoreTests` — Expected: FAIL.
- [ ] **Step 3: Implement `CaptureQueueStore`.**
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(ios): the capture queue`.

### Task 3: Notification words and money

**Files:**
- Create: `apps/mobile/ios/WambitoNative/Sources/WambitoNative/CaptureMoney.swift`
- Create: `apps/mobile/ios/WambitoNative/Sources/WambitoNative/CaptureAnswer.swift`
- Modify: `apps/mobile/scripts/gen-ios-strings.dart` (`keys`)
- Regenerate: `apps/mobile/ios/Runner/{es,en,it,pt}.lproj/Notices.strings`
- Test: `.../WambitoNativeTests/CaptureMoneyTests.swift`, `.../CaptureAnswerTests.swift`

**Interfaces:**
- Produces:
  - `public enum CaptureMoney { static func format(cents: Int64, currency: String, language: String) -> String }` — port of Android `widget/Money.kt` `formatMoney`.
  - `public struct CaptureAnswer { id, cents (signed), currency, name, categoryName, isFallback, merged, needsReview }` with `static func parse(_ json: [String: Any]) -> CaptureAnswer?` — port of `CaptureApi.kt` `parseCaptureAnswer` (reads `result`, `transaction.{id,amount,currency,name,needsReview}`, `category.{name,fallback}`).
  - `public static func CaptureAnswer.noticeId(_ txId: String) -> String` = `"wambito.capture.<txId>"`.
  - `func noted(template: String, fallbackTemplate: String, language: String) -> String` — sign `+` only when `cents > 0`, Android's `%1$s %2$s %3$s` order.

- [ ] **Step 1: Write the failing tests** — copy every case of `android/app/src/test/kotlin/com/wambito/app/widget/MoneyTest.kt` into `CaptureMoneyTests`; `CaptureAnswerTests`: a `created` answer parses; `merged` sets `merged`; a missing `transaction.id` → nil; `noted` gives `"Anoté −$18.000 en Juan Valdez · Café, ¿bien?"` for es/COP −1_800_000 and the fallback template when `category.fallback` is true.
- [ ] **Step 2: Run** `swift test --filter 'CaptureMoneyTests|CaptureAnswerTests'` — Expected: FAIL.
- [ ] **Step 3: Implement both files.**
- [ ] **Step 4: Add** `capture_noted`, `capture_noted_fallback`, `capture_confirm`, `capture_change` to `keys` in `gen-ios-strings.dart`; run `cd apps/mobile && dart run scripts/gen-ios-strings.dart`.
- [ ] **Step 5: Run** the Swift tests and `flutter test test/tooling` — Expected: PASS (the staleness check included).
- [ ] **Step 6: Commit** `feat(ios): the words and money of the capture notification`.

### Task 4: `wambito/capture` on iOS and the run

**Files:**
- Create: `apps/mobile/ios/Runner/Capture/CaptureChannel.swift` (app engine)
- Create: `apps/mobile/ios/Runner/Capture/CaptureQueueChannel.swift` (headless engine)
- Create: `apps/mobile/ios/Runner/Capture/CaptureRun.swift`
- Create: `apps/mobile/ios/Runner/Capture/CaptureSettings.swift`
- Modify: `ios/Runner/Background/BackgroundChannel.swift` (pass `captured`), `HeadlessRunner.swift`
  (register `CaptureQueueChannel`; completion gets `(outcome, captured)`), `SyncTask.swift` (adapt to the new completion), `AppDelegate.swift` (`registerChannels`), `project.pbxproj`
- Modify: `.github/channel-allowlist.txt` (remove `wambito/capture  # ios-impossible`)

**Interfaces:**
- Consumes: `CaptureQueueStore`, `CaptureAnswer` (Tasks 2–3), `HeadlessRunner.run`.
- Produces:
  - `HeadlessRunner.run(entrypoint:budget:completion: (String, [[String: Any]]) -> Void)`.
  - `enum CaptureSettings` (UserDefaults): `walletOn: Bool` — **unset counts as on** (a person who installed the shortcut and never opened the switch gets captures; my call), key `wambito.capture.sources`; `configured: Bool`, key `wambito.capture.configured`, set by the first `created` answer, cleared when the switch goes off.
  - `enum CaptureRun { static func send(completion: ((String) -> Void)? = nil) }` — if the store has items for the session owner: `HeadlessRunner.run(entrypoint: "captureMain", budget: 20)`; on `done`/`changed` `refuse` the keys still queued with `maxRefusals`; post or remove notifications per answer (Task 5's `CaptureNotices.announce`); `changed` → `BackgroundChannel.app?.vaultChanged()`. Any other outcome keeps the queue.
  - App-engine methods: `status` → null below iOS 17, else `{access: "granted", sources: walletOn ? ["apple_wallet"] : [], available: ["apple_wallet"], configured, iosMajor}`; `setSource {source, enabled}`; `openAccessSettings`/`openAppInfo` → false; `clearQueue`; `sendQueued {userId, from?}` → `adopt` then `CaptureRun.send()`; `takeQueued {userId}`; `ackQueued {keys, confirms}`; `dismiss {ids}`; `keepOnly {ids, before}`; `test` (Task 5).
  - Headless methods: `takeQueued`, `ackQueued` (as the app engine's).
  - `SyncTask.handle` calls `CaptureRun.send()` after its `syncMain` run (a queue left by a cut-off run goes out with the next sync); the app start needs nothing new: Dart already calls `sendQueued` on every start.

- [ ] **Step 1: Write the failing Dart test** in `test/capture_auto/capture_platform_test.dart`: a mocked `wambito/capture` answering `status` with `available: ['apple_wallet'], configured: true, iosMajor: 27` gives `AutoCaptureStatus(available: {'apple_wallet'}, configured: true, iosMajor: 27)`; an answer without `available` (Android) gives `available` = Revolut and Google Wallet's wires.
- [ ] **Step 2: Run** `flutter test test/capture_auto/capture_platform_test.dart` — Expected: FAIL.
- [ ] **Step 3: Extend `AutoCaptureStatus`** with `Set<String> available`, `bool configured` (default false), `int? iosMajor`; add `CaptureSource.appleWallet('apple_wallet', 'Apple Pay', null)` and make `brand` nullable (rows without a logo use `LkIcon(LkIconName.coin)`; no Apple logo).
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Implement the Swift files above**, add them to `project.pbxproj` (group `Capture`), remove the allowlist line.
- [ ] **Step 6: Verify** `scripts/check-channels.sh` passes, `flutter build ios --simulator --debug` builds, and `swift test` still passes.
- [ ] **Step 7: Commit** `feat(ios): the capture queue's channel and run`.

### Task 5: The action and the notification

**Files:**
- Create: `apps/mobile/ios/Runner/Capture/LogWalletPaymentIntent.swift` (intent + `WambitoShortcuts: AppShortcutsProvider`)
- Create: `apps/mobile/ios/Runner/Capture/CaptureNotices.swift`
- Modify: `AppDelegate.swift` (`NoticeTaps.didReceive` handles the actions; register the category at launch), `project.pbxproj`
- Create: `apps/mobile/ios/Runner/{es,en,it,pt}.lproj/AppIntents.strings` (titles below)

**Interfaces:**
- Consumes: `WalletPayment`, `CaptureQueueStore`, `CaptureSettings`, `CaptureRun`, `CaptureAnswer`.
- Produces:
  - `LogWalletPaymentIntent`: `openAppWhenRun = false`; `@Parameter(title: "Monto") var amount: IntentCurrencyAmount`, `@Parameter(title: "Comercio") var merchant: String`, `@Parameter(title: "Tarjeta") var card: String?`; `perform()` returns `.result()` with no dialog, never throws: off switch → return; `WalletPayment.read(amount: amount.amount, currencyCode: amount.currencyCode, merchant:)` nil → return; `add(…, source: "apple_wallet")`; `await` `CaptureRun.send`.
  - Titles: es "Anotar pago de Wallet" / en "Log Wallet payment" / it "Registra pagamento Wallet" / pt "Registrar pagamento da Wallet"; parameters es Monto, Comercio, Tarjeta (en Amount, Merchant, Card; it Importo, Esercente, Carta; pt Valor, Estabelecimento, Cartão).
  - `enum CaptureNotices`: category `wambito.capture` with actions `wambito.capture.ok` (title `capture_confirm`, no foreground) and `wambito.capture.change` (`capture_change`, foreground); `announce(_ answers: [CaptureAnswer])`: `merged && !needsReview` → remove `noticeId`; else post `.passive`, no sound, `threadIdentifier` `wambito.capture`, title "Wambi", body `noted(…)`, `userInfo["link"] = "wambito://review/<id>"`, `userInfo["transactionId"]`; `test()` posts the same body for an invented payment (`CaptureAnswer` with name "Prueba de Wambito"/en "Wambito test", fallback category) under category `wambito.capture.test` (no actions) — the "Probar" dry run: nothing queued, nothing saved (my call; the spec leaves it to the builder).
  - "Bien": `store.addConfirm(txId)`, `CaptureRun.send`, then remove the notification if the id left `confirms`. "Cambiar"/tap: the existing link path.

- [ ] **Step 1: Write the failing Swift test** (WambitoNative, pure part): `CaptureAnswerTests` gains `link == "wambito://review/<id>"` for an answer.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL, then implement `CaptureAnswer.link`, run again — PASS.
- [ ] **Step 3: Implement the intent, the provider and `CaptureNotices`;** wire `NoticeTaps` and the category registration.
- [ ] **Step 4: Verify on the iPhone 18 Pro simulator** with the dev stack (`NEW_USERS_ENCRYPTED=true`) and `--dart-define=WAMBITO_SERVER=http://localhost:3000`: in Shortcuts, a manual shortcut with "Anotar pago de Wallet" (Monto 18000 COP, Comercio "Cafe de prueba"), Wambito not running → a transaction to review appears, a silent notification shows, **Bien** confirms it with the app closed; with the switch off, the same run stores nothing (Review Focus 2); two runs within a second both end saved (Review Focus 5).
- [ ] **Step 5: Commit** `feat(ios): the anotar pago de wallet action and its notification`.

### Task 6: Settings on iOS

**Files:**
- Modify: `apps/mobile/lib/capture_auto/auto_capture_section.dart`, `how_capture_works.dart`
- Create: `apps/mobile/lib/capture_auto/wallet_setup.dart` (`walletShortcutUrl`, `showWalletSetup(context, iosMajor:)`, the iOS 27 steps sheet and the iOS 17–26 guide sheet)
- Modify: `apps/mobile/lib/l10n/app_{es,en,it,pt}.arb`
- Test: `test/capture_auto/auto_capture_section_test.dart`, `test/capture_auto/wallet_setup_test.dart`, `test/l10n/capture_copy_test.dart`

**Interfaces:**
- Consumes: `AutoCaptureStatus.available/configured/iosMajor`, `CaptureSource.appleWallet`, the `test` channel method.
- Produces: `const walletShortcutUrl = '';` (the founder fills it; empty ⇒ the guide); `Future<void> showWalletSetup(BuildContext, {required int iosMajor})`; `AutoCapturePlatform.testCapture()` → `Future<bool>` over `test`.

- [ ] **Step 1: Write the failing widget tests**
  - Rows come from `status.available`: an iOS status shows only `autoCapture.apple_wallet` with line `autoCaptureConfigured` ("Configurada") or `autoCaptureNotConfigured` ("Sin configurar") while on, `autoCaptureOff` while off; no `autoCapture.missing` / `grant` / `stuck` rows.
  - iOS rows `autoCapture.setup` ("Configurar en Atajos") and `autoCapture.test` ("Probar") show only when `available` has `apple_wallet`; tapping `autoCapture.test` calls `testCapture`.
  - First switch-on on iOS shows the how sheet ending in `autoCapture.setup.start` ("Configurar en Atajos"), which opens `showWalletSetup`.
  - `showWalletSetup(iosMajor: 27)` with a non-empty `walletShortcutUrl` (inject it through a parameter for the test) shows four steps and `walletSetup.install` launching that URL; with an empty URL or `iosMajor: 26` shows the guide with `walletSetup.openShortcuts` launching `shortcuts://`.
  - The how sheet's iOS variant uses `autoCaptureHowIos*` copy (reads amount, merchant and card name of Apple Pay payments only; processed on the phone; not payments with the physical card).
  - Turning the iOS switch off shows `autoCapture.remove` ("Quita la automatización en Atajos"), launching `shortcuts://` (spec section 5).
  - Android statuses render exactly as today (existing tests unchanged).
- [ ] **Step 2: Run** `flutter test test/capture_auto test/l10n` — Expected: FAIL.
- [ ] **Step 3: Implement**, with the arb keys in es, en, it, pt. Steps copy (es): 1 "Toca Instalar el atajo y agrégalo en Atajos." 2 "Abre el atajo y toca Editar." 3 "Toca el recuadro «La automatización está desactivada» y actívala." 4 "Paga una vez con el iPhone desbloqueado. Desde ahí funciona solo." Guide (es): Atajos → Automatización → + → Transacción → elige tus tarjetas → Ejecutar de inmediato → Siguiente → «Anotar pago de Wallet» → Monto, Comercio y Tarjeta con los datos de la transacción → Listo. Illustrations: Wambi scenes already shipped (`assets/wambi/capture-step*.webp`), no Apple screenshots.
- [ ] **Step 4: Run** `flutter test` (whole mobile suite) and `flutter analyze` — Expected: PASS, no issues.
- [ ] **Step 5: Commit** `feat(mobile): set up apple pay capture from settings on the iphone`.

### Task 7: Docs, policy, end to end

**Files:**
- Modify: `apps/mobile/AGENTS.md` (line 6 and the iOS section: `Capture/`, the queue file, the action, the category), `docs/mobile/ios.md` (new "The Wallet shortcut" section: build it on an iPhone with iOS 27 — automation Transaction, all cards, no confirmation, action "Anotar pago de Wallet" with the trigger's Amount, Merchant and Card; share as iCloud link; put the link in `walletShortcutUrl`), `docs/privacy-policy.md` and the web's `legal.privacy` copy in es, en, it, pt (iPhone paragraph: what the action receives, that it stays on the phone, how to remove the automation).

- [ ] **Step 1: Write the docs above.**
- [ ] **Step 2: Run the CI checks locally:** `pnpm lint`, `pnpm typecheck`, `scripts/check-channels.sh`, `scripts/check-old-name.sh`, `cd apps/mobile && flutter analyze && flutter test`, `cd ios/WambitoNative && swift test` — Expected: all pass.
- [ ] **Step 3: Repeat Task 5 Step 4 on the simulator from a clean install** and take screenshots of Settings → Captura automática, the setup sheet and the notification for the PR.
- [ ] **Step 4: Commit** `docs: wallet capture on the iphone`, push, open the PR; say in it that Figma (screens map) needs the iOS setup screens if Figma is not connected, and list spec section 7's iPhone checks (items 1, 2, 3, 5, 6) as open before release.
