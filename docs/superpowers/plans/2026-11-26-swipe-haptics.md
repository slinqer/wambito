# Haptics and swipe (PR 2 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The phone vibrates when the month changes, when the account button is tapped and when any segmented switch changes; swiping a movement feels like turning a watch crown and bounces home; the swipe actions draw the app's icons instead of emoji.

**Architecture:** New `FeedbackEvent`s for the fixed feels, plus a `hapticProvider` for the swipe's variable-scale detents. The detent spacing, scales, rate limit and the home spring live as constants and pure functions in `swipe_rules.dart`; `swipe_row.dart` plays them from its drag and from a listener on its spring. Icons come from `icons.json` (a new Plump Solid `pencil`), drawn by `LkIcon` on the phone and `Icon` on the web.

**Tech Stack:** Flutter (Riverpod 3), React (the web's `SwipeRow`).

**Spec:** `docs/superpowers/specs/2026-11-26-hide-amounts-design.md`, sections "Haptics" (month, account, segment, swipe) and "Swipe icons". Stacked on PR 1 (`feat/hide-amounts`).

## Global Constraints

- `pageChanged` stays `tick` 1.0, waveform `[15]`; it fires once per month moved, from the month picker's arrows (home, Análisis, category detail).
- `accountPressed`: `click` 0.45, waveform `[10]`. `segmentChanged`: `tick` 0.4 then `click` 0.7 after 30 ms, waveform `[6, 30, 12]`; only when the person picks another option (tap or keys), never when the value changes from code.
- Swipe detents: one every 20 logical px of travel, either way; `tick` scale from 0.25 (at rest) to 0.6 (at the threshold), waveform `[5]`; never closer than 25 ms (by frame time); the threshold keeps `thresholdCrossed`. On the spring home the same notches tick at scale × 0.6. The spring home overshoots a few px (underdamped) and its turn plays `swipeBounced` (`lowTick` 0.35, waveform `[8]`) once. Delete flying out and edit opening keep their feel.
- Every haptic obeys Settings' vibration switch.
- Swipe icons: `trash`, `check`, new `pencil` (Streamline Plump Solid "Pencil Diagonal", the founder's Pro licence, noted in `icons.json`), phone and web.

## Review Focus

- A fast flick: detents must not buzz (rate limit), and the threshold click still plays once.
- A swipe that opens Borrar (left) and stays open: no bounce tick, no return detents until it closes.
- Reduced motion: the row jumps (no spring), so no return detents and no bounce.
- A segmented control whose value the screen changes itself (a month with no expenses switching to income, say): silent.
- Vibration switch off: none of the new feels play.

---

### Task 1: The fixed feels (month, account, segments)

**Files:** Modify `lib/feedback/feedback_event.dart`, `lib/ui/month_picker.dart`, `lib/home/home_header.dart`, `lib/ui/segmented_control.dart`. Test: `test/feedback/feedback_test.dart`, `test/ui/month_picker_test.dart` (or the existing picker test), `test/ui/segmented_control_test.dart`, a home header test.

**Interfaces:** Produces `FeedbackEvent.accountPressed`, `FeedbackEvent.segmentChanged`, `FeedbackEvent.swipeBounced` (patterns in Global Constraints).

- [ ] Step 1: failing tests — the pattern table rows; tapping a month arrow plays `pageChanged` once; tapping the account button plays `accountPressed`; tapping another tab plays `segmentChanged`, tapping the selected one or changing `value` from outside plays nothing.
- [ ] Step 2: run them, FAIL.
- [ ] Step 3: implement with `context.feedback(...)` at each control.
- [ ] Step 4: run, PASS; commit `feat(mobile): the month, the account button and the switches have their feel`.

### Task 2: The crown and the bounce

**Files:** Modify `lib/ui/swipe_rules.dart`, `lib/ui/swipe_row.dart`, `lib/feedback/feedback.dart`. Test: `test/ui/swipe_rules_test.dart`, `test/ui/swipe_row_test.dart`.

**Interfaces:**
- Produces `final hapticProvider = Provider<void Function(HapticPattern pattern)>` (vibrates only while the switch allows); in `SwipeFeel`: `detent = 20.0`, `detentGap = Duration(milliseconds: 25)`, `detentLight = 0.25`, `detentFirm = 0.6`, `detentReturn = 0.6`, `rowHomeDamping` (underdamped, about 26), `bounce = 0.35`; pure `int notchOf(double offset)`, `double detentScale(double offset, double width)`, `HapticPattern detentPattern(double scale)`.

- [ ] Step 1: failing tests — `notchOf`/`detentScale` values; dragging a row 70 px over frames 30 ms apart plays 3 detents rising in scale; dragging fast (frames 5 ms apart) plays fewer; letting a short swipe go home plays return detents and one `swipeBounced`; an opened Borrar plays no bounce; reduced motion plays none.
- [ ] Step 2: run, FAIL.
- [ ] Step 3: implement (drag: compare notch on each move; spring home: a listener on `_x` while it animates to 0, ticks per notch, one bounce at the first turn past rest).
- [ ] Step 4: run, plus `test/ui` and `test/home`; PASS; commit `feat(mobile): swiping a movement turns like a crown and bounces home`.

### Task 3: The swipe icons

**Files:** Modify `docs/design/system/project/icons/icons.json` (`pencil`), `lib/ui/lk_icon_shapes.dart`, `apps/web/app/ui/icon-shapes.ts`, `lib/ui/swipe_row.dart`, `apps/web/app/ui/SwipeRow.tsx`. Test: `test/ui/lk_icon_test.dart`, `test/ui/swipe_row_test.dart`, `apps/web/app/ui/SwipeRow.test.tsx` (or its stories).

- [ ] Step 1: failing tests — the phone's swipe sides draw `LkIcon` `trash` / `check` / `pencil` and no emoji text; the web's swipe glyph is an `Icon`, not text.
- [ ] Step 2: run, FAIL.
- [ ] Step 3: download Pencil Diagonal, add it, swap the glyphs.
- [ ] Step 4: run phone and web tests; PASS; commit `feat(design): the swipe actions draw the app's icons`.

### Task 4: Review, phone check, PR

- [ ] `flutter analyze`, `flutter test --exclude-tags golden,stack`, web Vitest, `pnpm lint`, guards; AGENTS.md (haptics list, swipe feel); try it on the founder's phone; fresh final review; open the PR on `feat/hide-amounts` (Figma: swipe icons change, say so).
