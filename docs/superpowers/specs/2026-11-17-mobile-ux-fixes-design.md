# Mobile UX fixes from watching a real user (2026-11-17)

## Why

The founder watched a real person use the phone app. Five things got in the way: nobody finds the
widget, a fingerprint button on the first screen does nothing for a new person, the one-row widget
loses its buttons, "Listo" can be pressed while the voice is still being processed, and a quick
swipe deletes a movement by accident. Each fix is small and independent; they ship together on
`feat/mobile-ux-fixes`, one commit each.

## Approaches

Each point had one sensible way; the alternatives and why they lost are in each section.

## 1. Recommend the widget (Android)

- **When:** after the person's first saved movement (the founder's pick), a card on the home
  screen: Wambi, one line ("Anota sin abrir la app") and a button "Añadir widget".
- **How it adds:** `AppWidgetManager.requestPinAppWidget` for the medium widget (it has both the
  mic and ＋), which shows the launcher's own "Add to home screen" dialog. One tap, no tutorial.
- **Fallback:** when `isRequestPinAppWidgetSupported()` is false, the button opens a short
  three-step sheet instead (long-press the home screen → Widgets → Wambito).
- **Never shown again** once a Wambito widget exists (`getAppWidgetIds` of both providers > 0) or
  the person closes the card. Stored as a pref `wambito.widgetCard.closed`.
- **Settings:** the unused `settingsWidget` row gets an "Añadir widget" entry with the same action,
  next to "Ocultar el monto en el widget".
- **Channel:** three methods on the existing `wambito/device` channel: `widgetInstalled`,
  `widgetPinSupported`, `pinWidget`. iOS answers `false` / does nothing (no widget there yet), so
  the channel guard stays green without widening the allowlist.
- Rejected: an onboarding step before first use (the person does not yet know why they would want
  it); a system notification (feels like spam).
- iOS: out of scope until it has a WidgetKit widget.

## 2. Fingerprint on the first screen

- The button is "Entrar con huella" (passkey sign-in), shown on `/entry` whenever the phone
  supports passkeys, so a brand-new person taps it and nothing happens.
- **Fix:** remove it from `/entry`. Passkey sign-in stays inside "Entrar con mi correo", which
  already offers a stored passkey on open and skips guests.
- Rejected: keeping it but detecting whether a passkey exists (Credential Manager cannot tell
  without showing UI).

## 3. Widget at one row (4x1) and 2x1

- Today anything under 220×100dp is the SMALL layout, which has only ＋; the mic exists only in
  MEDIUM.
- **Fix:** a third Glance size, ROW, for wide and short (width ≥ 220dp, height < 100dp): amount,
  then 🎤 and ＋ on one line. SMALL (2x1) drops the label and keeps the amount, 🎤 and ＋ (smaller
  buttons, 36dp). MEDIUM keeps its 220×100dp threshold (a 4x2 is about 110dp tall), and its
  button column shrinks (40dp buttons, 4dp apart, 8dp padding) so it fits in 100dp and the mic is
  never clipped.
- Rule: every size shows both buttons.

## 4. "Listo" while the voice is refining

- While "Refinando…" shows (up to 3 s), "Listo" stays enabled and silently does nothing.
- **Fix:** "Listo" is disabled while `session.refining`, with the same dimmed look as `starting`.
  "Escribir" stays enabled: it is the way out when the person would rather type.

## 5. Swipe to delete

- Today a swipe past 40% of the row, or a flick of 500 px/s, deletes at once (with an 8 s undo).
- **Fix:** no swipe deletes by itself. Any release left past the half-open point, long or fast,
  leaves the row open with "Borrar" (the trash); only a tap on it deletes. The full-swipe commit
  and its haptic tick go. Undo stays as it is.
- Applies to home and category detail (both use `SwipeRow`). The web's `SwipeRow.tsx` is not
  changed here.

## Tests first

- Widget card: shows after the first movement, not before; hides once installed or closed;
  fallback sheet when pinning is unsupported (Dart widget tests with a fake device channel).
- Entry screen: no fingerprint button.
- Widget sizes: `widgetSizeFor` unit tests for 4x1, 2x1 and 4x2 (Kotlin).
- Capture: "Listo" disabled while refining.
- Swipe: `rowRelease` never returns delete for a long or fast swipe; it returns open.

## Left to the builder

Card copy and illustration within the design system; exact dp values of the ROW layout.
