# Mobile UX fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the five things a real user tripped on: no swipe deletes by itself, no fingerprint on
the first screen, "Listo" waits for the voice, both widget buttons at every size, and a card that
offers the widget after the first movement.

**Architecture:** Five independent changes in `apps/mobile`, one commit each, on
`feat/mobile-ux-fixes`. Dart for the swipe, entry, capture and the card; Kotlin Glance for the
widget sizes; a pin method on the existing `wambito/device` channel (Kotlin real, Swift `false`).

**Tech Stack:** Flutter (Riverpod 3, go_router), Kotlin + Glance (home_widget), Swift channel stub.

**Spec:** `docs/superpowers/specs/2026-11-17-mobile-ux-fixes-design.md`

## Global Constraints

- All commands from `apps/mobile` with `export PATH="$HOME/development/flutter/bin:$PATH"`.
- Tests first. Everything in code and tests in English; copy in the four ARBs `lib/l10n/app_{es,en,it,pt}.arb` (es is the template).
- Commits: `feat(mobile): …` / `fix(mobile): …`, lowercase sentence, stage by path, no `Co-Authored-By`.
- Persistent name added: pref `wambito.widgetCard.closed` (never rename without a migration).
- Channel guard: every method Dart calls on `wambito/device` exists in Kotlin and Swift; never widen `.github/channel-allowlist.txt`.
- Whoever changes structure updates `apps/mobile/AGENTS.md`.

## Review Focus

- A fast flick on a row whose delete is open already (start = −88) must still only stay open, never delete.
- Swipe right (Editar / Pagado) keeps its full-swipe commit; only the delete side changed.
- Refining that ends with `refine_failed` must re-enable "Listo" (refining goes back to false).
- The card must not show for a person with zero movements, nor flash while home is loading.
- On iOS the card and the Settings entry never show (pin unsupported and no widget there).

---

### Task 1: No swipe deletes by itself

**Files:**
- Modify: `apps/mobile/lib/ui/swipe_rules.dart` (`rowRelease`)
- Modify: `apps/mobile/lib/ui/swipe_row.dart` (`_onMove` armed/haptic for the left side)
- Test: `apps/mobile/test/ui/swipe_rules_test.dart`, `apps/mobile/test/ui/rows_test.dart`

**Interfaces:** Produces `rowRelease(...)` unchanged signature; it never returns `RowRelease.commitLeft`.

- [ ] **Step 1: Write the failing tests.** In `swipe_rules_test.dart` replace the left halves of
  "commits past the threshold" and "commits on a flick" with:
  `test('a long or fast swipe left only opens Borrar', ...)`:
  `release(-150, 0) == openLeft`, `release(-300, 0) == openLeft`, `release(-30, -700) == openLeft`,
  `release(-120, -2000) == openLeft`; the right side keeps `commitRight` for `release(150, 0)` and
  `release(30, 700)`. Keep "closes a tiny swipe, or one flung back" (`release(-20,0)`, `release(-80,700)` → close).
  In `rows_test.dart` add `testWidgets('a long fast swipe left leaves Borrar open and deletes nothing', ...)`:
  `t.fling(find.byType(SwipeRow), const Offset(-300, 0), 2000)`, settle, `find.text('BORRAR')` one,
  the `onDelete` counter is 0; then tap `BORRAR`, settle, counter is 1.
- [ ] **Step 2:** `flutter test test/ui/swipe_rules_test.dart test/ui/rows_test.dart` → the new cases FAIL (commitLeft).
- [ ] **Step 3: Implement.** In `rowRelease`, for `side == Side.left`: a flick toward it or past the
  threshold returns `openLeft` (no commit); a flick back still closes; otherwise the existing
  open/close by `openWidth / 2`. Update the doc comment. In `swipe_row.dart` `_onMove`, the left side
  is never armed (`Side.left => null`), so no threshold tick and no "pop" on Borrar.
- [ ] **Step 4:** same command → PASS; then `flutter test test/parity/swipe_row_parity_test.dart test/home test/budgets` → PASS (fix any test that expected a swipe delete by making it tap Borrar).
- [ ] **Step 5: Commit** `fix(mobile): a swipe only opens borrar, the tap deletes`.

### Task 2: No fingerprint on the first screen

**Files:**
- Modify: `apps/mobile/lib/entry/entry_screen.dart:76,104-121` (drop the `passkeys` watch, `_passkey`, `_Busy.passkey`, the button; drop unused imports)
- Test: `apps/mobile/test/entry/entry_test.dart` (or `entry_screens_test.dart`), goldens untouched unless they fail

- [ ] **Step 1:** Add `testWidgets('the first screen has no fingerprint button, even with passkeys', ...)`:
  `pumpApp(tester, auth: auth, passkeys: FakePasskeys())` on `/entry`, expect `find.byKey(Key('entry.passkey'))` nothing and `find.byType(FingerprintIcon)` nothing; then open `/entry/email` and expect `Key('entry.passkey')` one (it lives there).
- [ ] **Step 2:** run it → FAIL. Update the test at `entry_screens_test.dart:321-323` (it expects the passkey reachable on `/entry`) to open the email step first.
- [ ] **Step 3:** Remove the button and its state from `EntryScreen`. Keep the l10n keys if the email screen uses them; delete ones that become unused in all four ARBs.
- [ ] **Step 4:** `flutter test test/entry --exclude-tags golden` and `flutter analyze` → PASS.
- [ ] **Step 5: Commit** `fix(mobile): no fingerprint button on the first screen`.

### Task 3: "Listo" waits while the voice refines

**Files:**
- Modify: `apps/mobile/lib/capture/capture_listening.dart` (`CaptureListeningActions`)
- Test: `apps/mobile/test/capture/capture_sheet_test.dart` (next to "refining shows the label…", line ~691)

- [ ] **Step 1:** `testWidgets('Listo is disabled while refining, Escribir is not', ...)`: reach
  listening, `env.engine.refiningController.add(true)`, pump; the `PressButton` under
  `Key('capture.stop')` has `onPressed == null`, the one under `Key('capture.type')` does not; then
  `add(false)`, pump; `capture.stop` enabled again.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** "Listo"'s `onPressed` is `enabled && !session.refining ? session.stopListening : null` (the widget must rebuild on `refining`; it already does for the label, use the same listenable).
- [ ] **Step 4:** `flutter test test/capture --exclude-tags golden` → PASS.
- [ ] **Step 5: Commit** `fix(mobile): listo waits until the voice is refined`.

### Task 4: Both widget buttons at every size

**Files:**
- Modify: `apps/mobile/android/app/src/main/kotlin/com/wambito/app/widget/WidgetContent.kt`
- Test: `apps/mobile/android/app/src/test/kotlin/com/wambito/app/widget/WidgetContentTest.kt:100-108`

**Interfaces:** Produces `enum class WidgetSize { SMALL, ROW, MEDIUM }`; `widgetSizeFor(DpSize)`.

- [ ] **Step 1:** In `WidgetContentTest` change `widgetSizeFor(DpSize(250.dp, 50.dp))` to expect `ROW`, add `ROW` for `(320.dp, 70.dp)` and `(220.dp, 40.dp)`, keep SMALL for `(110.dp, 40.dp)` and `(180.dp, 110.dp)`, MEDIUM for `(230.dp, 104.dp)` and `(320.dp, 180.dp)`.
- [ ] **Step 2:** `cd android && JAVA_HOME=<JDK 17> ./gradlew :app:testDebugUnitTest --tests '*WidgetContentTest*' -x compileFlutterBuildDebug --console=plain` → FAIL.
- [ ] **Step 3:** `widgetSizeFor`: width ≥ 220 and height ≥ 100 → MEDIUM; width ≥ 220 → ROW; else SMALL. `widgetSizeMode` adds `DpSize(220.dp, 40.dp)`. `RoundButton` gains `size: Dp = 44.dp` (icon scales to ~55%). New `RowWidgetContent`: amount (one line, label above only if height allows — builder's call), then ＋ and 🎤 (40dp). `SmallWidgetContent`: no label, amount one line ellipsized, ＋ and 🎤 at 36dp. `MediumWidgetContent` button column: 40dp buttons, 4dp spacer, outer padding 8dp. `SizedWidgetContent` dispatches ROW. Signed-out content unchanged.
- [ ] **Step 4:** same Gradle command → PASS; full `:app:testDebugUnitTest` → PASS; `flutter test test/tooling/widget_android_test.dart` → PASS.
- [ ] **Step 5: Commit** `fix(android): the widget shows the mic and add buttons at every size`.

### Task 5: Pin the widget from the app (channel)

**Files:**
- Modify: `apps/mobile/android/app/src/main/kotlin/com/wambito/app/MainActivity.kt:145-165`
- Modify: `apps/mobile/ios/Runner/Device/DeviceChannel.swift`
- Create: `apps/mobile/lib/home/widget_pin.dart`
- Test: `apps/mobile/test/home/widget_pin_test.dart`

**Interfaces:** Produces in `widget_pin.dart`:
`class WidgetPin { Future<bool> installed(); Future<bool> supported(); Future<bool> pin(); }` over `MethodChannel('wambito/device')` methods `widgetInstalled`, `widgetPinSupported`, `pinWidget` (each answers a bool; any `PlatformException`/`MissingPluginException` → false), and `final widgetPinProvider = Provider<WidgetPin>(...)`.

- [ ] **Step 1:** `widget_pin_test.dart`: with `TestDefaultBinaryMessengerBinding` mocking `wambito/device`, each method returns what the handler answers; a missing handler gives false for all three.
- [ ] **Step 2:** run → FAIL (no file).
- [ ] **Step 3:** Dart class + provider. Kotlin: `widgetInstalled` = `getAppWidgetIds` of `WambitoSmallWidget` and `WambitoMediumWidget` receivers' `ComponentName`s, any > 0; `widgetPinSupported` = `AppWidgetManager.isRequestPinAppWidgetSupported()` (API ≥ 26, else false); `pinWidget` = `requestPinAppWidget(ComponentName(this, WambitoMediumWidget::class.java), null, null)`. Swift: all three `result(false)`; update the class comment.
- [ ] **Step 4:** `flutter test test/home/widget_pin_test.dart`, `../../scripts/check-channels.sh` → PASS.
- [ ] **Step 5: Commit** `feat(mobile): ask the launcher to add the widget`.

### Task 6: The widget card after the first movement, and in Settings

**Files:**
- Create: `apps/mobile/lib/home/widget_card.dart` (`WidgetCard`, `widgetCardProvider`, `showWidgetSteps` sheet)
- Modify: `apps/mobile/lib/home/home_screen.dart:537-542` (after `ReviewHomeRow`)
- Modify: `apps/mobile/lib/settings/settings_screen.dart:453-461` (an "Añadir widget" row before "Ocultar el monto…", Android and not installed only)
- Modify: `apps/mobile/lib/l10n/app_{es,en,it,pt}.arb`, `apps/mobile/AGENTS.md`
- Test: `apps/mobile/test/home/widget_card_test.dart`, a fake `WidgetPin` in it

**Interfaces:** Consumes `widgetPinProvider` (Task 5). Produces
`final widgetCardProvider = AsyncNotifierProvider<WidgetCardController, bool>` (true = show), with
`close()` (writes pref `wambito.widgetCard.closed` = true in the settings' secure storage, like the other prefs in `lib/settings/preferences.dart`) and `add()` (pinned when supported, else opens the steps sheet; after a pin, re-asks `installed()` on the next app resume).

Copy (es; translate the other three): `widgetCardTitle` "Anota sin abrir la app",
`widgetCardBody` "Pon a Wambi en tu pantalla de inicio: un toque y anotas el gasto, o díselo con 🎤.",
`widgetCardAdd` "Añadir widget", `widgetCardClose` "Ahora no",
`widgetStepsTitle` "Así añades el widget", steps `widgetStep1` "Mantén presionado un espacio vacío de tu pantalla de inicio.", `widgetStep2` "Toca «Widgets».", `widgetStep3` "Busca Wambito y arrástralo a tu pantalla.", `widgetStepsDone` "Entendido", settings row `settingsAddWidget` "Añadir widget" with hint `settingsAddWidgetHint` "Anota desde tu pantalla de inicio".

- [ ] **Step 1: Write the failing tests** (`pumpHome` from `test/home/home_harness.dart` with the fake pin, platform Android via `debugDefaultTargetPlatformOverride`):
  - `'no card while there are no movements'`: empty repo → `Key('home.widgetCard')` nothing.
  - `'the card shows once there is a movement'`: one movement → card one.
  - `'no card when a widget is already on the home screen'`: fake `installed() = true` → nothing.
  - `'Ahora no hides it for good'`: tap `Key('widgetCard.close')`, re-pump home → nothing; the pref is `true`.
  - `'Añadir widget asks the launcher when it can'`: tap `Key('widgetCard.add')` → fake `pin` called once.
  - `'Añadir widget shows the steps when the launcher cannot'`: `supported() = false` → `widgetStepsTitle` text shown.
  - `'never on iOS'`: platform iOS → nothing.
  - Settings: `'Settings offers Añadir widget on Android until one is added'` with `pumpSettingsApp`.
- [ ] **Step 2:** `flutter test test/home/widget_card_test.dart` → FAIL.
- [ ] **Step 3: Implement.** Card visible = Android && home loaded with ≥ 1 movement && !closed && !installed. Card built from the design system's card surface with Wambi (`assets/wambi/` happy face) and two `PressButton`s; steps in an `LkSheet`. Add the ARB keys, `flutter pub get` for l10n. AGENTS.md: a line under `lib/home` / widget about the card, its pref and the three `wambito/device` methods (Android real, iOS false).
- [ ] **Step 4:** `flutter test test/home test/settings test/l10n --exclude-tags golden`, `flutter analyze` → PASS.
- [ ] **Step 5: Commit** `feat(mobile): offer the widget after the first movement`.

### Task 7: Whole-branch check

- [ ] `flutter analyze`, `flutter test --exclude-tags golden,stack`, Gradle `:app:testDebugUnitTest`, `../../scripts/check-channels.sh`, `../../scripts/check-old-name.sh` → all PASS.
- [ ] On the emulator: swipe a row hard (Borrar stays open), first screen without fingerprint, the card after adding a movement and the launcher's pin dialog, widget resized to 4x1 and 2x1 with 🎤 and ＋.
