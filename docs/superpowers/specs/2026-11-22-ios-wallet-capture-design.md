# Wambito: automatic capture on iOS (v1: Apple Pay payments through Wallet)

- **Date:** 2026-11-22
- **Status:** approved 2026-11-23 (the installable shortcut of decision 6 added that day).
- **Follows:** `2026-11-04-automatic-capture-design.md` (Android, Revolut and Google Wallet) and
  `2026-11-11-ios-base-design.md`, which left capture out of iOS (`wambito/capture  # ios-impossible`).
- **Founder decisions (2026-11-22, in conversation):**
  1. iOS gets automatic capture, starting with **Apple Pay payments made with cards in Apple
     Wallet**, through the Shortcuts **Transaction** automation.
  2. Wambito **ships its own Shortcuts action** (an App Intent). The automation that calls it is
     either installed ready-made (decision 6) or built by the person with the app's guide; iOS does
     not let an app create an automation itself.
  3. **Bank SMS and email** (the Shortcuts Message and Email triggers) come in a later spec, on the
     same action, with parsers per bank.
  4. **Encrypted accounts only.** Plain (unencrypted) accounts no longer exist; their code is
     deprecated and will be removed, so nothing here supports them. **iOS 17 and later only.**
  5. Out: FinanceKit (Apple Card, Apple Cash and Savings in the US, UK connected accounts; an
     entitlement from Apple; nothing in Colombia), forwarding email to a Wambito inbox (the server
     would read the text: against end-to-end encryption), the SMS filter extension (unknown senders
     only, cannot store), open-banking aggregators (server side, paid).
- **Founder decisions (2026-11-23, in conversation):**
  6. **On iOS 27 the automation is installed ready-made**: Wambito offers an iCloud shortcut link
     whose shortcut carries the Transaction automation and the Wambito action (iOS 27 keeps an
     automation inside a shared shortcut). The person installs it, taps Editar, turns the
     automation on, and pays once with the phone unlocked. Prior art: Lukas by JotaTech
     (`lukas.jotatech.org/es/apple-pay`), the same four steps. **iOS 17 to 26** keep the guide of
     section 3.4. The founder makes the shortcut on his iPhone and shares its iCloud link; until
     the link exists the app shows only the guide.
  7. **Wallet first, Revolut later.** iOS 27 also has a Notification trigger (an app's
     notifications, optionally filtered by text), so Revolut can be read from its notifications on
     iOS in a later spec, with a parser like Android's. Nothing about Revolut here.
  8. Out for now: saving where the person paid (a location permission), which Lukas does.

## 1. Why and goal

Automatic capture is what people react to most; manual entry is the pain. On Android Wambito reads
bank notifications. iOS lets no app read another app's notifications, so the iPhone has had no
capture at all. The Shortcuts Transaction trigger ("When I tap [card] in Wallet", iOS 17+) is the
one place iOS hands an app a payment as it happens: amount, merchant, card name.

**Done when:** on an iPhone with the automation set up, a payment with Apple Pay shows up in
Wambito within seconds, with the app closed, as a transaction to review in the remembered
category (or "Otros gastos"), with a silent notification whose **Bien** confirms it without
opening the app. The same purchase reported twice (the trigger firing twice, or later an SMS of
the same purchase) is saved once.

**Non-goals:** payments with the physical card or card number (Wallet never sees them), income,
refunds, SMS and email (decision 3), creating the automation for the person, reading anything from
the bank apps.

**Anti-goals (a failure even if it works):** anything about the payment leaving the phone
unencrypted on an encrypted account; a capture lost because the app was closed or offline; a
setup the person cannot finish without outside help; a prompt on every payment ("Run
Immediately" must be on, so the automation never asks).

## 2. Approaches considered

1. **App Intent + Transaction automation (chosen).** Wambito declares an App Intent in an
   `AppShortcutsProvider`, so the action appears in Shortcuts as soon as the app is installed. The
   automation passes the trigger's fields to it. Runs in the background without opening the app.
   Setup: about five taps in Shortcuts, guided by the app.
   **Plus, on iOS 27 (chosen, decision 6):** an iCloud link to a ready-made shortcut whose
   Transaction automation calls this same action. Installing it replaces the guide's taps with
   import, Editar, turn the automation on. The action stays the only place a payment enters
   Wambito, so the shortcut holds no logic of its own.
2. **A shared iCloud shortcut that opens a `wambito://` link.** Nothing to build natively, but the
   app opens on every payment (or the link carries the payment in a URL), and nothing runs with
   the app closed. Rejected; a shared shortcut that calls the App Intent (above) keeps the one-tap
   install without these costs.
3. **FinanceKit.** The official API for Wallet transactions, but only for Apple's own US cards and
   UK connected accounts, behind an entitlement. Not usable in Colombia; revisit if Apple widens it.

## 3. iPhone

All new Swift lives in `apps/mobile/ios/Runner/Capture/`.

### 3.1 The action

- **`LogWalletPaymentIntent`** (`AppIntent`, `openAppWhenRun = false`), title "Anotar pago de
  Wallet" (localized es, en, it, pt), parameters:
  - **amount**: the trigger's Amount. Its exact type as passed by Shortcuts (a currency amount, a
    number, or text with the currency symbol) is checked in the spike (section 7); the intent
    turns it into integer cents and an ISO currency, never a float on the way.
  - **merchant**: text.
  - **card**: text, the card or pass name (kept only to show in the notification; not stored).
- Listed in an **`AppShortcutsProvider`**, so it needs no install and no "add shortcut" step.
- `perform()` validates (amount > 0, currency known, merchant not empty after trimming; else it
  returns quietly, nothing stored), builds a capture (kind `expense`, source **`apple_wallet`**,
  `capturedAt` = now in UTC), **queues it**, then starts the send (3.2) and returns. It never
  throws an error dialog in the person's face on a payment.
- If Wambito has no session (signed out, nothing ever set up), the capture is still queued and
  handed over on the next sign-in, as on Android.

### 3.2 Queue and send (same path as Android)

- **Queue:** a native queue with the same item shape as Kotlin's `ParsedCapture` plus the queue's
  `key` (read by `lib/background/queued_capture.dart`), stored under the same name,
  **`wambito.capture.queue`**, in the app's own container (no App Group: the intent runs in the app
  process). Excluded from backups like the vault (`excludeFromBackup`).
- **iOS side of `wambito/capture`:** `status`, `takeQueued`, `ackQueued`, `clearQueue`,
  `sendQueued` with Kotlin's meanings, so `SessionController`, `previewSyncProvider` and
  `CaptureHandover` work unchanged. Methods that only make sense on Android (notification access,
  restricted settings, per-app switches) answer with an iOS status instead (3.4).
- **Send right away:** after queuing, `perform()` runs **`captureMain`** in a
  `HeadlessRunner` (the one `SyncTask` uses), inside the intent's background time. The run writes
  the capture into the vault through the local `/v1` backend (`POST /v1/captures`, the queue key
  as `Idempotency-Key`), syncs, and acks. Only encrypted accounts exist, so the server only ever
  sees the sealed record; no capture goes to `POST /v1/captures` on the server. If the run cannot finish (`timeout`, `busy`, `failed`, offline), the
  queue keeps the item; the next `wambito.sync` task, app start or intent run sends it. Retry and
  drop rules are Android's (8 runs, `CaptureQueue.refuse` counting).
- The headless budget is cut to what the intent's background time allows (the spike measures it);
  the queue makes a cut-off run harmless.
- **If the spike shows the engine cannot start or finish inside `perform()`** (call made in this
  spec, to be confirmed by the founder with the spike results): the intent only queues, and posts
  a silent notification "Anoté −$18.000 en Juan Valdez; se guarda al abrir Wambito". The capture
  is written by the next app start or `wambito.sync` task. Swift never seals or writes the vault
  itself. The intent never opens the app.
- **Off switch:** the section has one switch, stored natively (`wambito.capture.sources`, as
  Kotlin's `setSource`). When it is off, `perform()` drops the payment without queuing, so a
  forgotten automation stores nothing.
- **iOS 16:** the Transaction trigger needs iOS 17, so the intent and `AppShortcutsProvider` are
  `@available(iOS 17, *)` and `status` answers null on iOS 16: the section stays hidden, as today.
- **Another currency:** the queue item carries the amount and the currency as Shortcuts gave them;
  the backend keeps them as on Android (amount as notified, original in the note). No conversion.

### 3.3 The notification

- After a `created` answer, a **silent** local notification through `Notices/NoticePoster`
  (`interruptionLevel = .passive`, no sound: Wallet already chimed): "Anoté −$18.000 en Juan
  Valdez · Café, ¿bien?"; a new merchant gets "… en Otros gastos, ¿qué categoría?". Same copy as
  Android's `CapturePoster`.
- Category `wambito.capture` with two actions: **Bien** (background action: queue a confirm, run
  `captureMain`, remove the notification) and **Cambiar** (opens `wambito://review/<id>`).
  Notification id from the transaction id, so `merged` updates the same one.
- The automation's own "Notify When Run" banner is left off in the guide, so there is one
  notification, ours.

### 3.4 Setup in the app

- **Settings → Captura automática** shows on iOS (it is hidden today because the channel is
  missing). One row: **"Pagos con Apple Pay"**, with state **Configurada** (a capture has arrived
  at least once, remembered in settings) or **Sin configurar**.
- The **"¿Cómo funciona?"** sheet (`how_capture_works.dart`) gets an iOS variant: what is read
  (amount, merchant, card name of Apple Pay payments, nothing else), that it is processed on the
  phone, what is stored, that it does not see payments with the physical card. It ends with
  **"Configurar en Atajos"**, which opens the iOS 27 steps or the guide, by the iOS version.
- **iOS 27 steps** (a sheet, like Lukas's page): 1 **"Instalar el atajo"** opens the shortcut's
  iCloud link (`https://www.icloud.com/shortcuts/<id>`) in Shortcuts, add it; 2 open it and tap
  **Editar**; 3 tap the box "La automatización está desactivada" and turn it on; 4 pay once with
  the phone unlocked, after which it runs locked. One illustration per step (copy only, no Apple
  screenshots). The link is one Dart constant (`walletShortcutUrl`), empty until the founder
  shares the shortcut; while it is empty, iOS 27 shows the guide below instead. The shortcut is a
  single Transaction automation (all cards, no confirmation before running) whose only action is
  "Anotar pago de Wallet" with Monto, Comercio and Tarjeta set to the trigger's fields; how to
  build and share it is written in `docs/mobile/ios.md`, so a new version can be made again.
- **Guide** for iOS 17 to 26 (and iOS 27 without a link) (a sheet with steps and one screenshot-like illustration per step, copy only, no
  Apple screenshots): open Atajos → Automatización → **+** → **Transacción** → choose the cards →
  **Ejecutar de inmediato** → **Siguiente** → action **"Anotar pago de Wallet"** (Wambito) → set
  Monto, Comercio and Tarjeta to the trigger's fields if Shortcuts did not fill them → Listo. A
  button opens Shortcuts (`shortcuts://`). The guide is reachable again from the section.
- **Test:** a "Probar" button in the section runs the same path with an invented payment marked
  as a test (shown and confirmed in the app, then deleted), so the person sees it work without
  paying. Whether a test capture goes through the real queue or a dry run is left to the builder.

### 3.5 Persistent names (fixed now)

The intent's type name `LogWalletPaymentIntent` and its parameter names (automations people built
point at them; renaming breaks every automation silently), the queue name `wambito.capture.queue`,
the notification category `wambito.capture`, the source wire name `apple_wallet`.

## 4. Shared data, server, web, MCP

- **New capture source `apple_wallet`** in `packages/core/src/capture-sources.ts`, the API's
  validation, the Dart port and the generated clients. Labels: "de Apple Wallet" in the review mark
  ("por revisar · de Apple Wallet"), in es, en, it, pt, on phone and web.
- **Forward compatibility (blocking):** `captureSource` is `z.enum(CAPTURE_SOURCES)` in
  `packages/core/src/records.ts`, and the Dart side mirrors it. An older web or phone that meets an
  `apple_wallet` record would fail to parse it and quarantine it, so the payment disappears there.
  Before any iPhone sends `apple_wallet`, a release of web and Android must read **any** source
  string (unknown ones shown with a generic "de captura" label). The builder confirms the parse
  path and orders the releases; the iOS capture ships only after that release is out. Phones that
  never update keep quarantining these records; that is accepted (they also miss every later
  feature), and no minimum version is forced.
- **Servers that do not know `apple_wallet`:** no issue. Captures are written to the vault on the
  phone and reach the server only as sealed records, so the server never validates the source.
  The API's schema still lists the value so the OpenAPI document and generated clients agree.
- Duplicate window and merchant memory unchanged: the 10-minute match is on kind, amount and
  currency, across sources, so a later SMS capture of the same purchase merges.
- **Server changelog:** a line under "Unreleased" in the root `CHANGELOG.md` for the new source.
- **MCP:** nothing new beyond accepting the source value in what it reads.
- **Privacy policy** (es, en, it, pt): the automatic-capture section gains iPhone: what the
  Shortcuts action receives, that it stays on the phone, how to remove the automation.
- **Channel guard:** `wambito/capture  # ios-impossible` leaves `.github/channel-allowlist.txt`;
  the guard then checks every method Dart calls has a Swift side.
- **`apps/mobile/AGENTS.md`**, `docs/mobile/ios.md` and the iOS base spec's "out" note are
  updated; the Figma screens map gets the iOS setup screens (or the PR says Figma was not
  connected).

## 5. Errors

- Offline, signed out, no time left: the capture stays queued; nothing is lost.
- Amount in another currency (paying abroad): saved as notified with the original in the note, as
  on Android.
- A trigger that fires twice for one payment: the duplicate window merges it.
- The person deletes the automation: nothing breaks; the section shows "Configurada" until they
  turn the switch off (3.2), which clears the remembered state and offers a link to Shortcuts to
  remove the automation.
- Shortcuts passes an empty or garbled field: the capture is dropped silently (as Android's
  unrecognized notifications).

## 6. Testing (failing test first)

- **Swift (`swift test` in `ios/WambitoNative` for the pure parts):** amount conversion to cents
  for every input form the spike finds (with thousands separators, decimals, pesos without
  decimals, euros, dollars), validation, the queue (add, take, ack, refuse, clear, survive a
  restart), the notification id rule.
- **Dart:** the iOS settings section states, the guide, the test button; `queued_capture.dart`
  reads an `apple_wallet` item; the review mark label.
- **Core and API:** the new source accepted; old-source records unchanged; a record with an unknown
  source parses (forward compatibility), on the TypeScript and Dart sides, from shared fixtures.
- **Stack e2e** (`run-vault-e2e.sh` style), if the iOS job can run it: a queued `apple_wallet`
  capture reaches `records` encrypted and is found by `psql` with no plain text.
- Manual on the founder's iPhone: a real Apple Pay payment end to end.

## 7. Spike before the plan

On the founder's iPhone, with a throwaway App Intent build:

1. The exact form of the Transaction trigger's **Amount** (type and text) with a Colombian card,
   and with a foreign currency if possible.
2. Whether the trigger fires for **online / in-app Apple Pay** or only for tap-to-pay in stores.
3. Whether Shortcuts fills the action's parameters from the trigger automatically or the person
   has to pick each variable (this changes the guide).
4. How much background time `perform()` gets, and whether a headless Flutter engine starts in it.
5. That "Ejecutar de inmediato" runs with the phone locked and the app not running.

6. That the shared iOS 27 shortcut (decision 6) arrives with its automation, runs without asking,
   and fires for every card, or what the person must still pick.

Changed 2026-11-23: these no longer block the plan. The simulator run (7.1) settled item 4, and
Lukas's shipping shortcut (7.2) shows item 6 works. The plan builds the amount reading for every
form Shortcuts is known to give (a currency amount, a number, text such as "$18.000" or
"COP 18.000,00"), so item 1 only adds test cases. Items 1, 2, 3, 5 and 6 are checked on the
founder's iPhone before the iOS capture is released, and any answer that changes a step goes back
into this spec and the guide.

### 7.1 Simulator results (2026-11-22)

Throwaway build on branch `spike/ios-wallet-intent` (worktree `.claude/worktrees/ios-wallet-spike`,
never merged): `LogWalletPaymentIntent` with an `AppShortcutsProvider`, a bare UserDefaults queue,
the headless engine's `wambito/capture` (`takeQueued`, `ackQueued`) and `captureMain` in
`HeadlessRunner`. iPhone 18 Pro simulator, iOS 27.2, Flutter debug build, local dev stack with
`NEW_USERS_ENCRYPTED=true`, a fresh guest (encrypted). The action was run from a manual shortcut
with fixed values (18000, "Cafe de prueba"), with Wambito not running.

- **Item 4: yes.** iOS launched the app in the background (`applicationState` 2) and `perform()`
  ran 3.5 s after launch (debug JIT). The headless engine started, took the queued item, wrote it
  through the local backend and synced: outcome `changed` in **1.5 s** (1.3 s on a second run with
  the process still alive). The server then held one more sealed `transaction` record (and the
  "Other expenses" fallback category) and no record body contained the merchant's text in clear.
  Section 3.2's send-right-away path holds; the fallback (queue only) stays as a safety net.
- **Duplicate window:** the same payment run twice within 10 minutes was merged (still one
  transaction).
- **Item 3, partly:** the action appears in Shortcuts with no install, titled "Anotar pago de
  Wallet", fields Monto, Comercio, Tarjeta. Whether the Transaction trigger fills them is still for
  the iPhone.
- **New, iOS 27:** Shortcuts says automations are now built into shortcuts, "including the ones
  you share". If a shared shortcut keeps a Transaction trigger with "Run Immediately", Wambito
  could offer one link that installs the shortcut with its trigger, cutting the guide to a tap or
  two. To check on the iPhone with the rest of section 7; the guide in 3.4 stays the plan until then.
- **Caveats:** a simulator, a debug build and the action run by hand, not by a payment. Timings on
  a phone, in release, from a locked screen, are for the iPhone run. The spike used the source
  `google_wallet` (the local backend rejects unknown sources) and the currency `COP`.

Items 1, 2, 3 (the trigger's fields), 5 and the shared-automation question wait for the iPhone.

### 7.2 Prior art: Lukas's Apple Pay shortcut (2026-11-23)

Lukas by JotaTech (`lukas.jotatech.org/es/apple-pay`, read 2026-11-23) ships one iCloud shortcut
link for iOS 27 ("Se abre en la app Atajos de tu iPhone · iOS 27") and a separate one with
other steps for iOS 26 and earlier. Its iOS 27 steps: import the shortcut, open it and tap Editar,
tap the box "Automation is turned off" and turn it on, make the first payment with the phone
unlocked (after that it runs without unlocking). It names no card choice and no run-mode switch.
So on iOS 27 a shared shortcut keeps its payment automation, off until the person turns it on.
Its page also lists bank shortcuts on iOS 27's Notification trigger (decision 7).

