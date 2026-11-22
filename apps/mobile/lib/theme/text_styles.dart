import 'package:flutter/painting.dart';

/// The web's text styles, with the size, weight, line height and letter spacing its CSS gives
/// them (the web is the source: apps/web/app/styles/app.css and the components in apps/web/app/ui).
/// Colour is not here: it comes from the theme's tokens, so `LkText.label.copyWith(color: ...)`.
///
/// Fredoka (display: titles and amounts) and Nunito (text) are bundled in assets/fonts, in the
/// weights apps/web/app/styles/fonts.ts loads (Fredoka 500-700, Nunito 600-900); each file is a
/// variable font, so the weight asked for here is the one drawn.
///
/// The web sets a line height only on some styles. The others inherit Tailwind's preflight
/// (`html { line-height: 1.5 }`), so they carry `height: 1.5` here and take the same room.
abstract final class LkText {
  /// tokens.css `--font-display`: the web's first choice of the display stack.
  static const displayFamily = 'Fredoka';

  /// tokens.css `--font-text`.
  static const textFamily = 'Nunito';

  /// Tailwind's preflight line height, which every style below without a CSS one inherits
  /// (node_modules/tailwindcss/preflight.css, `html`).
  static const _inherited = 1.5;

  /// `font-variant-numeric: tabular-nums`, which the web puts on its amounts.
  static const _tabular = [FontFeature.tabularFigures()];

  /// The keypad's amount: app.css `.lk-amount-display`, Fredoka 36px 700.
  static const display = TextStyle(
    fontFamily: displayFamily,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: _inherited,
    fontFeatures: _tabular,
  );

  /// The hero amount: app.css `.lk-hero-amount`, Fredoka 38px 700, line height 1.05.
  static const amountXl = TextStyle(
    fontFamily: displayFamily,
    fontSize: 38,
    fontWeight: FontWeight.w700,
    height: 1.05,
    fontFeatures: _tabular,
  );

  /// A row's amount: app.css `.lk-amount`, Fredoka 14px 600, tabular figures. The web's
  /// `white-space: nowrap` is the widget's (`softWrap: false`), not the style's.
  static const amount = TextStyle(
    fontFamily: displayFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: _inherited,
    fontFeatures: _tabular,
  );

  /// A sheet's title: apps/web/app/ui/Sheet.tsx `font-display text-[24px] leading-[1.15]
  /// font-bold`, Fredoka 24px 700.
  static const title = TextStyle(
    fontFamily: displayFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.15,
  );

  /// Running text: ConfirmSheet.tsx `text-[15px]` on the body's 700 (app.css `body`), Nunito.
  static const body = TextStyle(
    fontFamily: textFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: _inherited,
  );

  /// A row's title: app.css `.lk-rowtop`, Nunito 13px 800.
  static const label = TextStyle(
    fontFamily: textFamily,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    height: _inherited,
  );

  /// A row's status line: app.css `.lk-status`, Nunito 11px 800.
  static const caption = TextStyle(
    fontFamily: textFamily,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    height: _inherited,
  );

  /// A day header: app.css `.lk-overline`, Nunito 11px 900, `letter-spacing: 0.07em` (0.77 px at
  /// 11px) and upper case: run the text through [upperCase], Flutter has no `text-transform`.
  static const eyebrow = TextStyle(
    fontFamily: textFamily,
    fontSize: 11,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.07 * 11,
    height: _inherited,
  );

  /// A button's label: app.css `.lk-btn`, Fredoka 16px 700, `letter-spacing: 0.05em` (0.8 px),
  /// upper case ([upperCase]) and the 1.5 line height `font: inherit` takes from the page. The web
  /// centres the half-leading, which `leadingDistribution: even` does here.
  static const button = TextStyle(
    fontFamily: displayFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.05 * 16,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A small button's label: app.css `.lk-btn-sm`, [button] at 13px (letter spacing 0.05em of it).
  static const buttonSm = TextStyle(
    fontFamily: displayFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.05 * 13,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The "Pendiente" badge: app.css `.lk-badge`, Nunito 9.5px 900, `letter-spacing: 0.06em`
  /// (0.57 px), upper case.
  static const badge = TextStyle(
    fontFamily: textFamily,
    fontSize: 9.5,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.06 * 9.5,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A category chip's name: app.css `.lk-chip`, Nunito 10px 800.
  static const chip = TextStyle(
    fontFamily: textFamily,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The note under a chip's name: CategoryChip.tsx `text-[9px]` on the chip's weight, 800.
  static const chipNote = TextStyle(
    fontFamily: textFamily,
    fontSize: 9,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The glyph in a chip's tile: app.css `.lk-chip-tile`, 20px.
  static const chipGlyph = TextStyle(
    fontFamily: textFamily,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A segmented control's option: app.css `.lk-seg button`, Nunito 12px 900.
  static const segment = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w900,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The month picker's arrows: app.css `.lk-step`, Fredoka 18px 700.
  static const step = TextStyle(
    fontFamily: displayFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The month picker's name: MonthPicker.tsx `font-display text-lg font-semibold`, Fredoka 18px
  /// 600 on Tailwind's `text-lg` line height (28 px).
  static const monthName = TextStyle(
    fontFamily: displayFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 28 / 18,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Wambi's speech bubble: app.css `.lk-bubble`, Nunito 12px 800, line height 1.35.
  static const bubble = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    height: 1.35,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The glyph in a row's tile: app.css `.lk-tile`, 17px on the body's 700.
  static const tileGlyph = TextStyle(
    fontFamily: textFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A toast's message: app.css `.lk-toast`, Nunito 12px 800.
  static const toast = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A toast's action ("Deshacer"): app.css `.lk-toast-actions button`, the toast's text at 900.
  static const toastAction = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w900,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A swipe row's action: app.css `.lk-swipe-action`, Nunito 12px 900, `letter-spacing: 0.04em`
  /// (0.48 px), upper case ([upperCase]).
  static const swipeAction = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.04 * 12,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The glyph above a swipe action: app.css `.lk-swipe-glyph`, 18px with a line height of 1.
  static const swipeGlyph = TextStyle(
    fontFamily: textFamily,
    fontSize: 18,
    fontWeight: FontWeight.w900,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A keypad key: app.css `.lk-key`, Fredoka 18px 600.
  static const key = TextStyle(
    fontFamily: displayFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A text field's text: app.css `.lk-input`, Nunito 13px 800 (the input inherits it).
  static const input = TextStyle(
    fontFamily: textFamily,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A field's caption: AddTransactionSheet.tsx `text-[13px] font-bold text-ink-muted` on the
  /// labels of the date and the note, Nunito 13px 700.
  static const fieldLabel = TextStyle(
    fontFamily: textFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A name shortcut: app.css `.lk-shortcut`, Nunito 11px 800.
  static const shortcut = TextStyle(
    fontFamily: textFamily,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A bottom bar tab's label: app.css `.lk-tab`, Nunito 10px 800.
  static const tab = TextStyle(
    fontFamily: textFamily,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The wordmark: app.css `.lk-logo`, Fredoka 22px 700, line height 1. The web paints it with a
  /// gold to candy gradient clipped to the text (`LkWordmark` in home_header.dart does that).
  static const logo = TextStyle(
    fontFamily: displayFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The hero's label: Home.tsx `<h1 className="lk-hero-label m-0 text-[13px]">`: `.lk-hero-label`
  /// says 12px 800, and the `text-[13px]` utility wins, so Nunito 13px 800.
  static const heroLabel = TextStyle(
    fontFamily: textFamily,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The line under the hero's bar: app.css `.lk-hero-meta`, Nunito 11px 800.
  static const meta = TextStyle(
    fontFamily: textFamily,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A card's or a menu entry's own words, and a list's empty message: Home.tsx and HomeHeader.tsx
  /// `text-[14px] font-bold`, Nunito 14px 700.
  static const bodySm = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A nudge card's title: Home.tsx `text-[14px] font-extrabold`, Nunito 14px 800.
  static const cardTitle = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A nudge card's lead: Home.tsx `text-[12px] font-bold`, Nunito 12px 700.
  static const cardLead = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The entry screens' title: SignInScreen.tsx `ScreenTitle`, `font-display text-[28px]
  /// leading-tight font-bold`, Fredoka 28px 700 on Tailwind's `leading-tight` (1.25).
  static const screenTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A paragraph with no size of its own (`<p className="text-center text-ink-muted">`): the
  /// body's Nunito 700 at the browser's 16px, on Tailwind's 1.5.
  static const copy = TextStyle(
    fontFamily: textFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A note under a form, and a field's error: SignIn.tsx `text-[15px]`, FieldError `text-[15px]
  /// text-over`, Nunito 15px 700 on the inherited 1.5.
  static const note = TextStyle(
    fontFamily: textFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A field's label and the line between two ways in: SignIn.tsx `text-sm`, Nunito 14px 700 on
  /// Tailwind's `text-sm` line height (20px).
  static const labelSm = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 20 / 14,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A digit of the sign-in code: app.css `.lk-code-box`, Fredoka 26px 700 with tabular figures
  /// (the input takes the page's 1.5 line height).
  static const codeBox = TextStyle(
    fontFamily: displayFamily,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: _inherited,
    fontFeatures: _tabular,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A manage page's title: Settings.tsx `<h1 className="m-0 font-display text-[28px] font-bold
  /// text-ink">`, Fredoka 28px 700 on the inherited 1.5 (it has no leading of its own).
  static const pageTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: _inherited,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A settings card's title: parts.tsx `SettingsSection`, `font-display text-[20px] font-bold
  /// leading-tight`, Fredoka 20px 700 on Tailwind's 1.25.
  static const sectionTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `text-transform: uppercase`, for [eyebrow], [button], [buttonSm] and [badge].
  static String upperCase(String text) => text.toUpperCase();
}
