# Hide amounts (an eye on home for the whole app, one on the widget) and a widget that looks like the app

Date: 2026-11-26. Status: approved by the founder on 2026-11-26. Built in three PRs: hide amounts; haptics and swipe; the widget look.

## Intent

The founder wants to show the phone app to someone (a demo, handing the phone over) without showing
their money. One tap on an eye next to home's figure hides every amount in the app; another tap shows
them again. The home-screen widget gets its own eye, so its amount can be hidden or shown from the
home screen itself, without opening Settings. While the widget changes, it also gets closer to the app:
its figure in the app's typeface, its ＋ and 🎤 buttons as the app draws them today, and a picker
preview that shows the real widget instead of Wambi alone.

## Goals

- **App eye.** An eye button right next to home's hero figure ("Gastado este mes" / "Te quedan" /
  "Te pasaste"). Closed eye: every amount the phone app shows becomes `••••`. Open eye: amounts as
  today. The choice is kept (closing and reopening the app keeps it) until the eye is tapped again.
- **Whole app.** Hidden means every place an amount is shown: home (hero, meter, Wambi's line,
  transaction rows, the review row), movements, search (rows and the totals line), categories and
  category detail, budgets, recurring payments, insights (figures, the donut's and the trend's
  labels), the review inbox, the save toast, home's widget card and the merge screens. The list is
  the known places, not a limit: any amount the phone draws on screen is masked (builder: search
  every `formatMoney` and `Money` use).
- **Widget eye.** A small eye button on the Android widget (both sizes) toggles the widget's own
  "hide the amount" state without opening the app. It is the same state as Settings → Captura →
  Widget → "Ocultar el monto": flipping one flips the other.
- **Independent.** The app eye and the widget eye are two separate states. The app eye never
  changes the widget and the widget eye never changes the app (founder, 2026-11-26).

- **Widget figure in Nunito.** The big amount (or `••••`) is drawn in Nunito, the app's figure
  typeface, as on home's hero. Glance can only use the phone's system fonts, so the figure is drawn as
  an image (a bitmap made with the app's Nunito font file), sized to the widget and the screen
  density, coloured by the theme, with the amount (or "amount hidden") as its description for screen
  readers. The small labels (the month, "Te quedan", "Gastado este mes") keep the system font
  (founder, 2026-11-26).
- **Widget buttons like the app's.** ＋ and 🎤 match today's bottom bar: rounded squares with the
  darker bottom ledge, both filled brand purple with white icons from the app's icon set (Plump, as
  in `icons.json`), ＋ larger than 🎤. Today the widget draws circles and an outlined microphone, an
  older home design.
- **Picker preview.** The widget picker shows what each size looks like: one preview image per size
  (small and medium) made from the real widget with invented sample figures (a month, "Te quedan
  312,40 €", the eye open), replacing `previewImage="@drawable/wambi_happy"`. Night theme. How the
  images are made (a test that renders the widget, or a script over the emulator) is the builder's
  call; they are regenerated, never hand-drawn, and the command goes in `apps/mobile/AGENTS.md`.

## Haptics

New phone-only events in `lib/feedback/feedback_event.dart` (the ＋ and 🎤 press events are phone
only too, so the web's list needs no twin), each with a composition for Android 11+ and a waveform
for older motors, and all behind Settings' vibration switch like every other event (founder,
2026-11-26):

- **Amounts hidden: "the blind comes down and shuts."** Two light ticks gaining weight, ending in a
  dull knock: `tick` 0.4, `tick` 0.6 after 25 ms, `thud` 0.9 after 35 ms; waveform
  `[6, 25, 8, 35, 22]`.
- **Amounts shown: "the blind goes up."** The mirror: a soft low knock, then lighter and lighter,
  nothing final: `lowTick` 0.6, `tick` 0.5 after 35 ms, `tick` 0.3 after 25 ms; waveform
  `[16, 35, 8, 25, 6]`.
- Both fire from the app eye and from the widget eye (the widget's action plays the same pattern
  natively, through the same Kotlin code `HapticsChannel.kt` uses, and honours the same switch).
- **Month changed:** the existing `pageChanged` (`tick` 1.0, waveform `[15]`), which nothing fires
  yet and was kept for "the first pager": the month picker is it. It fires once per month moved,
  from the arrows and from any swipe that moves the month, wherever the month picker is (home,
  Análisis).
- **Account button:** `accountPressed`, a button smaller and quieter than the 🎤: `click` 0.45,
  waveform `[10]`, as the menu opens.
- **Segment changed:** `segmentChanged`, a switch that slides and snaps: `tick` 0.4 then `click` 0.7
  after 30 ms, waveform `[6, 30, 12]`. Fired inside `SegmentedControl` (`lib/ui/segmented_control.dart`)
  when the person picks another option, so every switch has it: Movimientos/Categorías on home,
  Gastos/Ingresos in Análisis, categories, search, the add sheet, recurring and the capture editor.
  Never fired when the value changes from code, only from a tap.

- **Swiping a movement feels like turning a watch crown** (founder, 2026-11-26). Today a row only
  ticks once at the threshold (`thresholdCrossed`). New:
  - *Detents while dragging:* a `swipeDetent` tick every 20 logical px the row travels, either way,
    like the notches of a crown. Light far from the threshold and firmer as it nears it (`tick`
    0.25 rising to 0.6; waveform `[5]` on older motors), never closer than 25 ms apart (a fast
    flick skips notches instead of buzzing). Crossing the threshold keeps its own firmer click.
  - *Detents on the way back:* when the finger lets go and the row springs home, the same notches
    tick as it passes them, quieter (scale × 0.6), so the row feels like it rolls back.
  - *The bounce:* the spring home gets a small visible overshoot (slightly underdamped, a few px past
    rest and back), and the turn at the overshoot's peak gives a soft `lowTick` 0.35, then nothing as
    it settles. The swipe that runs an action (delete flying out, edit opening) keeps its feel.
  - All in `lib/ui/swipe_row.dart` and `swipe_rules.dart` (the springs); the detent spacing and
    scales are constants there, to tune on the phone.
- The founder tries them on a phone once built; the numbers may be tuned then.

## Swipe icons

The swipe actions draw emoji today (`🗑` delete, `✓` mark paid, `✎` edit, `swipe_row.dart`). They
become the app's own icons (`LkIcon`): `trash`, `check`, and a new `pencil`, added to `icons.json`
from the same Streamline Plump set as the others (with its Dart copy and licence entry, as the
icons' rules say). The web's swipe is the twin (`.lk-swipe-glyph`) and reads the same `icons.json`,
so it changes the same way to keep parity (Claude's call).

## Non-goals

- The web app. Phone only for now.
- The capture notifications ("Anoté −4,10 € en …") and the "Hoy vence…" notice keep their amounts.
- Fields where the person types an amount (add, edit, budget form, import), and the capture preview
  card that shows what was just dictated or typed before saving: always visible, since someone
  entering a figure needs to see it (Claude's call, 2026-11-26).
- Exported files and shared text: they are files, not the screen.
- iOS has no widget; it gets the app eye only.

## Anti-goals

- An amount that stays visible somewhere after the eye is closed (a screen that only updates when
  left and opened again). For a demo that is the failure that matters.
- Hiding names, categories or dates: the app must still be understandable while hidden.

## Constraints (from the project)

- Money on screen goes through `formatMoney` (`lib/money/format.dart`) and the `Money` widget
  (`lib/ui/money.dart`), about 20 files. Wambi's line is built in `lib/home/wambi_line.dart` /
  `home_format.dart`.
- The widget's hide choice today is `HideWidgetAmount` (`lib/settings/preferences.dart`,
  `SecureFlagStore('setting.widget.hideAmount')`), read by `WidgetSync` and by the headless run
  (`background_main.dart` `_hideAmount`), and copied into the widget snapshot's `hideAmount`, which
  Kotlin draws (`WidgetModel.kt`). Kotlin cannot write flutter_secure_storage, so a widget button
  cannot flip that flag where it lives today.
- Persistent names on phones need a migration to change (`apps/mobile/AGENTS.md`, Traps).
- Many phone screens have web twins with parity tests (`docs/mobile/parity.md`); the eye is phone
  only.
- Screen changes update the Figma screens map, or the PR says so.

## Approaches

For hiding amounts:


1. **One shared state plus one amount painter (picked).** A new kept flag for the app eye; the
   `Money` widget and every `formatMoney` call that ends on screen read it through one provider and
   paint `••••`, so every screen redraws the moment it flips. The widget's flag moves to where Kotlin
   can write it. Cost: touching the ~20 call sites and one migration.
2. **A global switch inside `formatMoney`.** Fewer edits, but screens are not told: some figures stay
   visible until the screen is rebuilt. Rejected (the anti-goal).
3. **A blur over the screen.** Quick, but hides names and categories too and looks broken. Rejected.

The founder picked 1 (2026-11-26).

For the widget's figure: an image drawn with Nunito (picked; the only way to show a font of the app
in a widget) or the system font (today). Only the figure, not every label: the labels barely show
the difference and each image costs memory and work on resize (founder, 2026-11-26).

## Decided

- **App eye state:** a new kept flag (Dart only), default open (amounts shown). It is read by one
  provider (`amountsHiddenProvider`, the builder's name) that the amount painter watches. One flag
  per phone, not per account: it survives sign-out, another account's sign-in and a merge, since it
  is about who is looking at the screen (Claude's call).
- **Masked form:** `••••` (the widget's existing word, `widget_hidden`), the same for any amount and
  sign, so the masked text never hints at the size. Screen readers say "amount hidden" (the widget's
  `widget_amount_hidden` wording, new Dart strings in es, en, it and pt).
- **Charts:** keep their shapes (donut slices, trend bars); drop every amount label and amount in
  their semantics. Percentages: shown (they reveal proportions, not money).
- **Wambi's line:** while hidden, a line without amounts (the builder picks the line; e.g. the
  greeting without the figure).
- **The eye:** an icon button (eye / eye-off) right after the hero figure, with the labels "Ocultar
  montos" / "Mostrar montos" as its semantics, 48 dp tap target.
- **Widget state:** the source of truth for the widget's hide choice moves from secure storage to the
  widget's own preferences (the file Kotlin already reads, `HomeWidgetPreferences`), as its own key
  apart from the snapshot, so both the widget button and Settings' switch write it. Every writer of
  the snapshot reads that key at the moment it writes (the app's `WidgetSync`, the headless
  `widget_effect.dart`, Kotlin's `RefreshWorker`), never a cached copy, so a widget tap is never
  undone by a later sync (Claude's call). On first run after the update the old secure value is
  copied over once (a migration); a read that fails is retried at the next start and the copy is
  marked done only after it succeeds; while the key is missing or unreadable the widget hides the
  amount, as today's rule says (`widget_effect.dart`: never shown in the clear by guess). The old
  key is then ignored.
- **Widget button:** a Glance action (no activity opens) that flips the stored choice, rewrites the
  snapshot's `hideAmount` and redraws both widget sizes. The app reads the choice again on resume, so
  Settings' switch shows the new value. The eye shows only in the states that show an amount
  (signed in, with or without a stale mark); the signed-out widget has no amount and no eye, and the
  kept choice applies at the next sign-in (Claude's call).

## Left to the builder

- Exact names of the new flag, provider, keys and strings.
- Where the eye button sits in the widget layout for each size, and its icon asset.
- Whether masking is done by a `Money`-like widget only, or also a helper for strings that embed an
  amount (meter labels, toasts): whatever covers every case listed under Goals.
- Parity: mark the eye as a known phone-only difference in the parity list, or exclude it from the
  shots.
- Tests: a widget test per screen family that, with the flag on, finds no digit-bearing amount text;
  Kotlin tests for the widget action and the migration.
