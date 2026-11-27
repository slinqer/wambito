# Hide amounts (PR 1 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An eye next to home's hero figure that hides every amount in the phone app, and an eye on the Android widget that hides its amount, each with the "blind" haptics.

**Architecture:** The app eye is a Dart-only kept flag read at start (no flash), watched by one masking layer (`Money` widget + a `shownMoney` helper) that every on-screen amount goes through. The widget's own choice moves from secure storage to `HomeWidgetPreferences` (key `wambito.widget.hideAmount`), the one place both Dart and a Glance action can read and write; every snapshot writer reads it at write time.

**Tech Stack:** Flutter (Riverpod 3), Kotlin + Jetpack Glance 1.2, home_widget.

**Spec:** `docs/superpowers/specs/2026-11-26-hide-amounts-design.md` (sections Goals, Decided, Haptics: the two blind patterns). PRs 2 (haptics and swipe) and 3 (widget look) get their own plans after this merges.

## Global Constraints

- Masked text is exactly `••••` for any amount and sign; screen readers read "amount hidden" (new strings below).
- App eye: one flag per phone, default shown, survives sign-out, account switch and merge; independent of the widget eye.
- Never masked: fields where an amount is typed (add, edit, budget form, import), the capture preview card, Settings' currency sample, the how-it-works demos, notifications, exported files, the web.
- Widget choice: unreadable or not yet migrated ⇒ hidden; never shown by guess.
- Haptics: `amountsHidden` = `tick` 0.4, `tick` 0.6 after 25 ms, `thud` 0.9 after 35 ms, waveform `[6, 25, 8, 35, 22]`; `amountsShown` = `lowTick` 0.6, `tick` 0.5 after 35 ms, `tick` 0.3 after 25 ms, waveform `[16, 35, 8, 25, 6]`; both obey Settings' vibration switch.
- Repo rules: failing test first; persistent names need a migration (new keys are new names, list them in `apps/mobile/AGENTS.md` Traps); Conventional Commits, no Co-Authored-By line; stage by path.

## Review Focus

- Cold start with the eye closed: home's first frame shows no amount (the flag is in `InitialSettings`, not read lazily). Test in Task 2.
- Amounts inside sentences (the meter's "€4.10 of €100", the save toast, Wambi's line, review notices) slip past a `Money`-only change. `expectNoAmounts` scans text and semantics. Tests in Tasks 4–5.
- A widget tap while the app runs in the background, then a vault sync: the sync must not put the old choice back. Test in Task 6 (`WidgetSync` reads the store, not a cached flag).
- The migration reading secure storage fails: the widget hides and the copy retries next start. Test in Task 6.
- Toggling the eye with a sheet or another route open: every visible amount flips at once. Test in Task 5 (search screen open over home).

---

### Task 1: The `eye` icon

**Files:**
- Modify: `docs/design/system/project/icons/icons.json`, `apps/mobile/lib/ui/lk_icon_shapes.dart`, `apps/mobile/lib/ui/lk_icons.dart` (`LkIconName.eye`), the licence/credit line if the icon list is named there.
- Test: `apps/mobile/test/ui/lk_icon_test.dart` (already checks the Dart copy equals `icons.json`).

**Interfaces:** Produces `LkIconName.eye` (open eye); `LkIconName.eyeOff` exists.

- [ ] **Step 1:** Fetch "eye" from the same Streamline set as `eye-off` (Plump; check `icons.json`'s comment for the exact set) with the Streamline tools; add it to `icons.json` in the file's format.
- [ ] **Step 2:** Run `flutter test test/ui/lk_icon_test.dart`. Expected: FAIL (Dart copy missing `eye`).
- [ ] **Step 3:** Add the Dart copy and `LkIconName.eye`.
- [ ] **Step 4:** Run the same test and `pnpm vitest run --project @wambito/web` for any icon-name test on the web. Expected: PASS.
- [ ] **Step 5:** Commit `feat(design): the eye icon`.

### Task 2: The app eye's state

**Files:**
- Create: `apps/mobile/lib/privacy/hide_amounts.dart`
- Modify: `apps/mobile/lib/settings/settings_store.dart` (`hideAmountsKey`), `apps/mobile/lib/settings/initial_settings.dart`
- Test: `apps/mobile/test/privacy/hide_amounts_test.dart`, `apps/mobile/test/settings/initial_settings_test.dart`

**Interfaces:**
- Produces: `const hideAmountsKey = 'setting.app.hideAmounts'` (values `on` / `off`); `InitialSettings.hideAmounts` (`bool`, default `false`); `class HideAmounts extends Notifier<bool>` with `Future<void> set(bool hidden)`; `final amountsHiddenProvider = NotifierProvider<HideAmounts, bool>(...)`.

- [ ] **Step 1: Write the failing tests**

```dart
test('reads on as hidden at start, anything else as shown', ...);   // InitialSettings.read
test('starts from the initial settings, so the first frame is already hidden', () {
  final c = ProviderContainer(overrides: [initialSettingsProvider.overrideWithValue(
      InitialSettings(serverUrl: defaultServerUrl, themeMode: ThemeMode.dark, hideAmounts: true))]);
  expect(c.read(amountsHiddenProvider), isTrue);
});
test('set keeps the choice in the settings store', ...);  // store.read(hideAmountsKey) == 'on' / 'off'
test('a store that fails to write keeps the choice for this run', ...);
```

- [ ] **Step 2:** Run `flutter test test/privacy test/settings/initial_settings_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement, following `ThemeModeSetting` (`lib/settings/preferences.dart`): state from `initialSettingsProvider`, write through `settingsStoreProvider`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat(mobile): keep the hide-amounts choice`.

### Task 3: The masking layer and the blind haptics

**Files:**
- Create: `apps/mobile/lib/privacy/masked_money.dart`, `apps/mobile/test/support/amounts.dart`
- Modify: `apps/mobile/lib/ui/money.dart`, `apps/mobile/lib/feedback/feedback_event.dart`, the four ARBs
- Test: `apps/mobile/test/privacy/masked_money_test.dart`, `apps/mobile/test/feedback/feedback_test.dart`

**Interfaces:**
- Produces: `const hiddenAmount = '••••'`; `String shownMoney(bool hidden, int cents, String currency, String locale, {MoneySign sign = MoneySign.auto})`; `Money` reads `amountsHiddenProvider` itself (becomes a `ConsumerStatefulWidget`, same constructor); `FeedbackEvent.amountsHidden`, `FeedbackEvent.amountsShown` with the patterns in Global Constraints; l10n `amountHidden`, `hideAmounts`, `showAmounts`, `homeWambiHidden`; test helper `void expectNoAmounts(WidgetTester tester)`.
- Copy (es / en / it / pt):
  - `amountHidden`: "Monto oculto" / "Amount hidden" / "Importo nascosto" / "Valor oculto"
  - `hideAmounts`: "Ocultar montos" / "Hide amounts" / "Nascondi gli importi" / "Ocultar valores"
  - `showAmounts`: "Mostrar montos" / "Show amounts" / "Mostra gli importi" / "Mostrar valores"
  - `homeWambiHidden`: "Tus montos están ocultos. Toca el ojo para verlos." / "Your amounts are hidden. Tap the eye to see them." / "I tuoi importi sono nascosti. Tocca l'occhio per vederli." / "Os teus valores estão ocultos. Toca no olho para os ver."

- [ ] **Step 1: Write the failing tests**

```dart
test('shownMoney masks any amount and sign the same way', () {
  expect(shownMoney(true, -410, 'EUR', 'es'), '••••');
  expect(shownMoney(true, 123456789, 'USD', 'en'), '••••');
  expect(shownMoney(false, -410, 'EUR', 'es'), formatMoney(-410, 'EUR', 'es'));
});
testWidgets('Money shows •••• and reads "amount hidden" while hidden, and flips live', ...);
testWidgets('expectNoAmounts fails on "4,10 €", "€4.10", "1.234 USD" and passes on "••••"', ...);
test('the blind patterns', () {
  expect(hapticPatterns[FeedbackEvent.amountsHidden]!.waveform, [6, 25, 8, 35, 22]);
  expect(hapticPatterns[FeedbackEvent.amountsShown]!.waveform, [16, 35, 8, 25, 6]);
  // primitives: names, scales and delays exactly as in Global Constraints
});
```

`expectNoAmounts` scans every `Text`/`RichText` string and every semantics label for
`RegExp(r'(\d[\d.,   ]*\s?(€|\$|£|\b[A-Z]{3}\b))|((€|\$|£)\s?\d)')`.

- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement. While hidden `Money` skips its count-up and its semantics say `amountHidden`. Run `flutter pub get` for the ARBs.
- [ ] **Step 4:** Run them, plus `test/l10n`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(mobile): mask amounts and the blind haptics`.

### Task 4: The eye on home

**Files:**
- Modify: `apps/mobile/lib/home/home_widgets.dart` (hero), `apps/mobile/lib/home/wambi_line.dart` / `home_format.dart`, `apps/mobile/lib/home/home_screen.dart`, `apps/mobile/lib/ui/transaction_row.dart`, `apps/mobile/lib/home/widget_card.dart`, the review row
- Test: `apps/mobile/test/home/hide_amounts_home_test.dart`

**Interfaces:** Consumes Tasks 2–3. Produces key `home.hideAmounts` (an `IconButton`-like 48 dp target right after the hero figure; `LkIconName.eye` while shown, `eyeOff` while hidden; semantics label `hideAmounts` / `showAmounts`).

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('the eye hides every amount on home and Wambi says why', (t) async {
  // pumpHome with a summary that has budgets and a few movements
  await t.tap(find.byKey(const Key('home.hideAmounts')));
  await t.pump();
  expectNoAmounts(t);
  expect(find.text(l10n.homeWambiHidden), findsOneWidget);
  expect(feedback.events, [FeedbackEvent.amountsHidden]);
});
testWidgets('a second tap shows them again with the shown haptic', ...);
testWidgets('started hidden, the first frame has no amount', ...); // initialSettings hideAmounts: true, expectNoAmounts after the first pump
```

- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement: the button calls `set(!hidden)` and `context.feedback(hidden ? amountsShown : amountsHidden)`; every string on home that embeds money uses `shownMoney(ref.watch(amountsHiddenProvider), …)`; Wambi's line returns `homeWambiHidden` while hidden.
- [ ] **Step 4:** Run, plus `test/home`. Expected: PASS (fix goldens only if they are not among the known Mac failures; compare with the base first).
- [ ] **Step 5:** Commit `feat(mobile): an eye on home hides every amount`.

### Task 5: Every other screen

**Files (modify each place money reaches the screen):** `lib/insights/{insights_screen,cost_of_living,trend_chart,category_donut,charts,insights_model,insights_controller}.dart`, `lib/ui/category_row.dart`, `lib/search/search_screen.dart`, `lib/budgets/{budget_sheet,category_detail_screen,categories_tab}.dart`, `lib/recurring/recurring_row.dart`, `lib/review/*`, `lib/add/save_outcome.dart`, `lib/merge/merge_screen.dart`. Find any other with `grep -rn "formatMoney(\|Money(" lib`; leave the Global Constraints' never-masked places as they are.
- Test: `apps/mobile/test/privacy/screens_hidden_test.dart`

- [ ] **Step 1: Write the failing tests:** one `testWidgets` per family, each pumping the screen with fixture data, flag on, then `expectNoAmounts(t)`: search (rows + totals), categories tab, category detail, budget sheet, recurring list, insights (both kinds; charts keep their shapes, percentages may stay), review screen, the save toast, the merge currency stop. Plus `'toggling with search open over home masks both at once'`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Route each amount through `Money` or `shownMoney`; chart semantics drop amounts.
- [ ] **Step 4:** Run, plus `flutter test --exclude-tags golden,stack` and `flutter analyze`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(mobile): hidden amounts across the app`.

### Task 6: The widget's choice moves where the widget can write it

**Files:**
- Create: `apps/mobile/lib/home/widget_choice.dart`, `apps/mobile/android/app/src/main/kotlin/com/wambito/app/widget/WidgetChoice.kt`
- Modify: `lib/settings/preferences.dart` (`HideWidgetAmount.store`), `lib/home/widget_sync.dart`, `lib/background/background_main.dart` (`_hideAmount`), `lib/feedback/vibration_setting.dart` (mirror), `lib/app.dart` (reload on resume), `RefreshWorker.kt`
- Test: `apps/mobile/test/home/widget_choice_test.dart`, `apps/mobile/test/home/widget_sync_test.dart`, `android/app/src/test/kotlin/com/wambito/app/widget/WidgetChoiceTest.kt`

**Interfaces:**
- Produces (Dart): `const widgetHideAmountKey = 'wambito.widget.hideAmount'`, `const widgetVibrationKey = 'wambito.widget.vibration'` (values `on` / `off`, in `HomeWidgetPreferences` through `WidgetStore`); `class WidgetPrefsFlagStore implements FlagStore` (`WidgetPrefsFlagStore(WidgetStore store, {required FlagStore legacy})`); `HideWidgetAmount.reload()`.
- Produces (Kotlin): `object WidgetChoice { fun hideAmount(context: Context): Boolean; fun setHideAmount(context: Context, hidden: Boolean); fun vibrationOn(context: Context): Boolean }` (missing key: `hideAmount` falls back to the snapshot's `hideAmount`, else `true`; `vibrationOn` missing = `true`).
- Migration: `read()` with the key missing reads `legacy` (`SecureFlagStore('setting.widget.hideAmount')`): `null` ⇒ write `off`, return `null`; a value ⇒ write it, return it; a throw ⇒ write nothing, return `true` (hidden; retried next start).

- [ ] **Step 1: Write the failing tests**

```dart
test('migrates a kept secure choice once', ...);          // legacy on ⇒ key on, legacy not read again
test('never chosen migrates as shown', ...);             // legacy null ⇒ key off, read null
test('an unreadable legacy hides and retries next start', ...); // read true, key still missing
test('WidgetSync writes the stored choice, not a stale cached one', ...); // flag notifier says false, store says on ⇒ snapshot hideAmount true
test('vibration switch is mirrored to the widget prefs', ...);
```
Kotlin: `WidgetChoiceTest`: key wins over snapshot; missing key falls back to snapshot; nothing at all ⇒ hidden; `setHideAmount` writes the key and the snapshot's `hideAmount`; `RefreshWorker`'s signed-out snapshot uses `WidgetChoice.hideAmount`.

- [ ] **Step 2:** Run (`flutter test test/home`; Kotlin per `apps/mobile/AGENTS.md` Commands). Expected: FAIL.
- [ ] **Step 3:** Implement. `WidgetSync`, `widget_effect`'s caller and `RefreshWorker` read the store at write time; `app.dart`'s resume hook calls `reload()`.
- [ ] **Step 4:** Run both suites. Expected: PASS.
- [ ] **Step 5:** Commit `feat(android): the widget's hide choice lives with the widget`.

### Task 7: The eye on the widget

**Files:**
- Create: `android/app/src/main/kotlin/com/wambito/app/widget/ToggleHideAmount.kt`, `res/drawable/ic_widget_eye.xml`, `res/drawable/ic_widget_eye_off.xml` (from `icons.json`'s `eye` / `eye-off`), `android/app/src/main/kotlin/com/wambito/app/haptics/Blinds.kt`
- Modify: `WidgetContent.kt` (both sizes, signed-in states only), `HapticsChannel.kt` (extract `fun playHaptic(context: Context, spec: HapticSpec): Boolean` for reuse), `res/values*/strings.xml` (`widget_hide_amount`, `widget_show_amount` in es/en/it/pt, same words as `hideAmounts` / `showAmounts`)
- Test: `android/app/src/test/kotlin/com/wambito/app/widget/ToggleHideAmountTest.kt`, `apps/mobile/test/tooling/blinds_android_test.dart`

**Interfaces:** Consumes `WidgetChoice` (Task 6). Produces `class ToggleHideAmount : ActionCallback`; `object Blinds { val HIDDEN: HapticSpec; val SHOWN: HapticSpec }`.

- [ ] **Step 1: Write the failing tests:** `ToggleHideAmountTest`: a tap flips the choice and the snapshot, asks both widget sizes to redraw, plays `Blinds.HIDDEN` / `SHOWN`, and plays nothing when `vibrationOn` is false. `blinds_android_test.dart`: reads `Blinds.kt` and checks its numbers equal Dart's `hapticPatterns` for the two events (as `widget_android_test.dart` does for the widget).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. The eye sits next to the figure (exact place per size is the builder's call), 48 dp target, `contentDescription` from the strings; signed-out content has none.
- [ ] **Step 4:** Run Kotlin tests and `flutter test test/tooling`; `scripts/check-channels.sh` unaffected. Expected: PASS.
- [ ] **Step 5:** Commit `feat(android): an eye on the widget`.

### Task 8: Docs, emulator check and PR

- [ ] **Step 1:** Update `apps/mobile/AGENTS.md` (the privacy folder, the new persistent keys `setting.app.hideAmounts`, `wambito.widget.hideAmount`, `wambito.widget.vibration` under Traps) and `docs/design` if the icon list is described.
- [ ] **Step 2:** Run `pnpm lint`, `pnpm typecheck`, `flutter analyze`, `flutter test --exclude-tags golden,stack`, Kotlin unit tests. Expected: all pass.
- [ ] **Step 3:** On the emulator against the local stack: tap home's eye (every screen masked, haptic), restart the app (still hidden, no flash), tap the widget's eye from the home screen (widget masks; Settings' switch follows on return), screenshots for the PR.
- [ ] **Step 4:** Push `feat/hide-amounts`, open the PR (Figma: home gains the eye; say so if not updated), bind it.
