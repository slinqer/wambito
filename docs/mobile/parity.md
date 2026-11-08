# Parity: the app against the web, picture by picture

Stage 3b's rule is that the app looks like the web (spec
`docs/superpowers/specs/2026-10-23-stage-3b-mobile-parity-design.md`, §4 and §5). The parity
harness checks it. Each **pair** is a web Storybook story in one theme and an app test that
renders the same thing as a golden, at the same size, from the same data. A review picture puts
the two side by side, with the pixels that differ marked.

## The loop

From the repository root (Flutter on PATH: `export PATH="$HOME/development/flutter/bin:$PATH"`):

```sh
pnpm --filter @wambito/web parity:fixtures        # the stories' data → apps/mobile/test/parity/fixtures
pnpm --filter @wambito/web parity:shots           # the stories' pictures → apps/mobile/test/parity/web
cd apps/mobile
flutter test --update-goldens test/parity       # the app's pictures → test/parity/app
dart run tool/parity/compose.dart --max 2       # side by side → build/parity; fails over 2% of ink
```

Each command takes an optional id filter, e.g. `parity:shots money` or `compose.dart money`.

For a review of every pair at once, `dart run tool/parity/index.dart` (after `compose.dart`) writes
`build/parity/index.html`: each pair's picture, its ink share and its known-difference note, worst
first. It is git-ignored.

Then open `apps/mobile/build/parity/<id>-<theme>.png`:

- top left: the web;
- top right: the app;
- underneath: the web in grey, with every differing pixel in magenta, and the two shares below.

### What differs, and the pass rule

- **A pixel differs** when its colour on one side is nowhere within one logical pixel (two physical
  pixels, at the parity's ratio of 2) of the same place on the other side. Colours count as the
  same within 24 of 255 per channel.
  - That forgives what spec §5 allows: antialiasing, and text that Chrome and Flutter round to
    different pixels (see "Known differences").
  - It does not forgive a wrong size, weight, colour or spacing.
- **The ink share** is the measure: differing pixels over the pixels that are not the page's
  background on either side. The share of the whole page is printed too, but a small component on
  an empty page is almost all background, so that number says little.
- **A pair passes** when:
  - the picture shows no visible difference except those spec §5 allows: the system bars, the 🎤
    next to the ＋, the web-only demo banner, and text antialiasing; and
  - **under 2% of its ink differs.** `compose.dart --max 2` exits non-zero when a pair is over.
- Look at the picture first. The number backs it up; it does not replace it.

How the rule was set, on Money (compose's unit tests pin the tolerances):

| | Ink that differs |
| --- | --- |
| The true Money pairs | 0.00% on all 7 |
| Probe: Money's colour at 85% alpha | 64% to 85% (all 7 over) |
| Probe: Money's font 1 px bigger | 26% to 35% (all 7 over) |
| A tolerance of ±1 physical pixel instead, true pairs | 20–22% for the hero amount |

The last row is why the shift tolerance is a logical pixel, not a physical one. Blink rounds line
metrics to whole CSS pixels, so the hero amount sits 2 physical pixels away. With ±1 physical
pixel, the true pair would fail the 2% rule.

`compose.dart` writes both shares for every pair to `build/parity/summary.json`.

Once the app's side is right, plain `flutter test test/parity` is the regression test: it fails
when the app's picture changes. The web shots are regenerated only when the web changes.

## Adding a pair

1. Add the pair to `apps/mobile/test/parity/parity.json`, once per theme:

   ```json
   { "id": "money-spanish", "storyId": "ui-money--spanish", "theme": "night",
     "appTest": "test/parity/money_parity_test.dart" }
   ```

   - `id` is the file stem: `web/<id>-<theme>.png` and `app/<id>-<theme>.png`.
   - `storyId` is the Storybook id, as in the URL's `?id=`.
   - Every shared screen and component has a pair in `night` and in `day`. A story that pins
     `globals: { theme: "day" }` only has a day pair; the shots script refuses the other one.

2. Write the app test first, so it fails before the widget exists. Mark the file
   `@Tags(['golden'])` and call:

   ```dart
   await parityGolden(t, 'money-spanish', screen, theme: 'night');
   ```

   - Pass `locale: const Locale('en')` for a story with `globals: { locale: "en" }`.
   - A component's story goes in `ParityStoryFrame`, which is what Storybook's decorator puts
     around it: the page background, 16px padding, and the body's text as the line it sits on.
   - A story whose root is a block (a `div`: a flex column, a grid, a `max-w` box) is not an inline element on
     the body's line: pass `ParityStoryFrame(block: true, ...)`, and make the box as a CSS block is
     with `cssBlock(maxWidth: ...)`, `lkPad` and `lkRowFlex` (`.lk-pad`, `.lk-row-flex`).
   - A full-screen story (`layout: "fullscreen"`, its own screen) is passed as is.

   A story's `play` function leaves the page in a state (a focus ring after `userEvent.click`, a
   month stepped back, a button held with `is-pressed`). Pass `act:` to `parityGolden` to do the same
   in the app, with real taps, keys and held fingers: `t.sendKeyEvent(LogicalKeyboardKey.tab)`
   puts the app in keyboard mode, where the focused control draws its ring, as the story's click
   does in Chrome (`userEvent` focuses from script, which counts as keyboard). Do the taps first and
   the keys last: a tap puts the app back in touch mode, where no ring shows.

3. Read the story's data from its fixture: `ParityFixtures.load(storyId)`.
   - `fixture.get('/v1/summary?month=2026-10').body` is the JSON the story's fake API answered.
   - `fixture.now` is the clock the story ran at. `parityGolden` pins the app's `clockProvider`
     to it.

4. Run the loop, look at the picture, and fix the app until the picture shows no visible
   difference and `compose.dart --max 2` passes. Commit the web shot, the fixture and the golden.
   `build/parity` stays out of git.

## How the two sides are made the same

- **Size.** 412 × 915 logical pixels at a device pixel ratio of 2, so both pictures are 824 × 1830.
  On the web it is the Playwright viewport. In the app it is the test view.
- **Clock.** Both sides use the e2e suite's "now", 21 October 2026 at 15:00 UTC (`E2E_NOW`), in
  Europe/Madrid.
  - The shots and the fixtures pin the page's clock before anything loads, with the demo stories'
    own `fakeClock` (`apps/web/app/demo/fake-clock.ts`). The stories' "today" and month (for example
    `STORY_TODAY`) therefore come out the same on any real date.
  - The fixture records that time, and `parityGolden` gives it to the app.
- **Data.** A story harness hands its fake `fetch` to `exposeStoryFetch`
  (`apps/web/.storybook/parity.ts`). `HomeStage`, the demo's `DemoStage` and `SignInStage` do. A
  harness for a new kind of screen does the same.
  - `parity:fixtures` opens the story and lets it render and play.
  - Then it asks that same fake API every GET the story made, plus the app's GETs (`APP_GETS` in
    `apps/web/scripts/parity-fixtures.ts`).
  - When a screen needs a GET that is not there, add it to `APP_GETS`.
  - Keys are the API path without the web's `/api` mount, with the query sorted:
    `GET /v1/transactions?limit=50&month=2026-10`.
  - A component's story has no fake API, so its fixture has only the clock.
- **Theme.** The shots open `iframe.html?id=<story>&globals=theme:<theme>`, which is what the
  toolbar's theme does (`.storybook/preview.tsx`). The app test uses the app's `nightTheme` or
  `dayTheme`.
- **Settling.**
  - The shots wait for Storybook's "finished" phase, after the story has rendered, played and
    finished its animations.
  - Then they take pictures until two in a row are identical. CSS animations are taken at rest:
    finite ones at their end, endless ones (Wambi's sprite) at their first frame.
  - The app test uses `pumpAndSettle`.
- **Fonts.** Both sides draw Fredoka and Nunito, from the web's `@fontsource` files and from the
  app's bundled upstream files.
- **Emoji.** Both sides draw emoji with Noto Color Emoji (SIL OFL 1.1). The font is committed
  unmodified in `apps/mobile/test/parity/fonts` with its licence. It is test-only and never goes
  into the APK.
  - The shots add it to each of the page's font faces, for the emoji code points only. Chrome then
    draws it instead of the Mac's Apple Color Emoji.
  - The font keeps its pictures as PNGs in `CBDT` tables. `flutter test` on macOS draws through Core
    Text, which only draws Apple's `sbix` tables. So `test/support/emoji_font.dart` moves the same
    PNGs into an `sbix` table, in memory, for the goldens.
  - The file is googlefonts/noto-emoji's `2D/fonts/NotoColorEmoji.ttf` (the CBDT build, version
    2.057, Emoji 18), unmodified and not subset:
    - source commit `e20cbc2bbec1926686be9f9bee7d1d2cfa1fea0e` (the font last changed in
      `1ffdd21391dd`, "Add Emoji 18 fonts");
    - SHA-256 `15671215ab769fdc7162a045d56fd7d7e477c51b04e6b3c761d914d8fdd6cc44`, 10,730,124 bytes;
    - `NotoColorEmoji-OFL.txt` is that commit's `2D/fonts/LICENSE`.
  - It is test-only. Nothing in pubspec.yaml names it, and the release APK's assets hold only
    Fredoka, Nunito and the tree-shaken Material icons.
  - To update it, replace both files from a newer commit, record the commit and SHA-256 here, and
    run the loop. Take the CBDT `NotoColorEmoji.ttf`, not a COLRv1 build: `sbixFromCbdt` reads CBDT.
  - `test/parity/emoji_font_test.dart` checks that `sbixFromCbdt` converts the committed file. It
    also fails when an emoji in any fixture, or anywhere in the web's and the app's code, has no
    picture in it, so a missing emoji is reported rather than drawn as a box.
- **Randomness.** Home's Wambi picks one of three phrasings of a line at random. The shots pin
  `Math.random` to 0 (`RANDOM_SCRIPT` in `apps/web/scripts/parity-storybook.ts`), so every picture shows
  the first phrasing, and the home pairs ask the app for it too (`wambiVariantProvider`).
- **The story's page.** Storybook pads every story by 16px (`.storybook/preview.tsx`) while the bottom bar
  stays fixed to the viewport, and the web's background gradient is as tall as its page (a long list
  stretches it, and `min-h-dvh` keeps a short page a screen tall) and scrolls away with it. A screen pair puts
  the app's screen in a `ShellFrame` (`lib/ui/app_shell.dart`) with that padding (which the screen puts inside its
  scroll content, `ShellRoom.leading` and `ShellRoom.sides`, so it scrolls as Storybook's does), no 🎤 (`showMic`)
  and, for the demo, a stand-in of the banner (`banner`). The gradient is the app's own, in the app and in the
  pairs: the shell paints it as tall as its screen's scroll content (at least the screen) and moves it with
  the scrolling (`PageGradientPainter`, from the scroll notifications). In the app itself the frame is zero.
- **Stories that end with a sheet open.** `home-home--empty-month` opens the add sheet and closes it again
  (the story's play function was changed to close it), so its picture is the empty month.
- **The add and edit sheet (`add-sheet-*`).** Four stories leave the sheet open: `home-home--more-options` (Más
  opciones opened, pending ticked; its old tail, which saves, is now `MoreOptionsSent`),
  `home-home--shortcut-picks-category`, `home-home--sheet-day-theme` (pesos, with the lukas hint) and
  `home-home--edit-sheet-day-theme`. The sheet opens over home, as in the stories, and the app reads the names the
  story's API suggested through `FixtureAddRepository`. A story's `userEvent` click leaves the focus on what it
  clicked; the test asks for it after a key (`_clickFocus`).
  - **The date field is the browser's own.** The web's `<input type="date">` is drawn by Chrome: here as
    `21.10.2026` with a black calendar. The app writes the date as the language does (`21/10/2026`, `10/21/2026` in
    English), so the `more-options` pairs differ in those two separators, and draws Chrome's calendar after it.
  - **The pending checkbox is Chrome's too:** 20px, the brand as its accent, and, with the keyboard on it, Chrome's
    blue and white focus ring; the app paints the same.
- **Shadows.** `flutter test` draws every shadow hard-edged, to keep goldens from flaking. The web's
  glow under a primary button is a 24px blur, so `parityGolden` turns `debugDisableShadows` off for
  the picture and back on before the test ends.
- **The ✓ of "Pagado".** Nunito has no ✓. Chrome on the Mac falls back to Zapf Dingbats (found with
  CDP's `CSS.getPlatformFontsForNode`) and thickens it, because the badge asks for weight 900 and that
  font has one. Flutter's tests thicken nothing. So both sides draw U+2713 from the Mac's own
  `/System/Library/Fonts/ZapfDingbats.ttf`, at the face's own weight (`useParityEmoji`,
  `loadParityFonts`). It is Apple's, so it is read from the Mac, never committed. On a phone, Android's
  fallback font draws it, and thickens it in both Chrome and Flutter.
- **⌫ and ＋.** No web font has them, so Chrome on the Mac falls back: ⌫ (the keypad's backspace) to San
  Francisco (`.SF NS`, because the stacks end in `ui-rounded, system-ui`), ＋ (the bottom bar's add button)
  to PingFang SC Semibold (found with CDP's `CSS.getPlatformFontsForNode`). `flutter test` has no
  fallback, so the golden harness names the same system files: `/System/Library/Fonts/SFNS.ttf`, and the
  `PingFang.ttc` of macOS's downloaded font asset (face 11 is `PingFangSC-Semibold`, taken out of the
  collection by `ttcFace`). Apple's, read from the Mac, never committed. On a phone Android's fallback
  draws them.
- **✓ and ✎ are a known test-font difference** until NotoSansSymbols2 (OFL) is in the harness. Neither is in a
  web font, so Chrome falls back to a system font and the Flutter golden harness names macOS Zapf Dingbats
  (`test/support/emoji_font.dart`, `loadParityFonts`). For ✓ both sides use Zapf Dingbats (the shots read it
  from the Mac too); for ✎ Chrome picks another font than Zapf Dingbats, so the glyph differs visibly. A pair
  that draws one of them carries a `knownDifferences` note in `test/parity/parity.json`, and
  `compose.dart` prints it on the pair's line (`KNOWN DIFFERENCE: ...`) and writes it to `summary.json`: a
  pass there is not proof of that glyph. The pairs:
  - ✓: `pending-badge-idle-to-paid`, `pending-badge-day-english`, `transaction-row-pending`,
    `name-field-pick-shortcut`, `name-field-typing`, `name-field-day-english`.
  - ✎: `swipe-row-open-day-english` (the Editar action).
  Remove the notes when the symbol font replaces Zapf Dingbats on both sides.
- **Icons.** Material icons draw with the Flutter SDK's own `MaterialIcons-Regular.otf`
  (`loadMaterialIcons` in `test/support/fonts.dart`), the file `flutter build` bundles. The Stage 3
  goldens load it too.

## Known differences

- **Inline line boxes.** Blink rounds a font's ascent and descent to whole pixels and floors the
  half-leading. Flutter does neither.
  - `ParityStoryFrame` places its child on the body's line the way Blink does (`cssStrutAscent`).
  - A text style whose line height is smaller than its font's own (`.lk-hero-amount` at 1.05) still
    sits up to one logical pixel lower in the app than in Chrome.
  - That is within spec §5's one-pixel wobble. compose's one-logical-pixel tolerance forgives it.
- **Glyph rasterising.** Chrome and `flutter test` rasterise the same glyphs a little differently:
  edges differ by a physical pixel here and there, which the tolerance forgives too.
- **What the tolerance hides.** An element off by one logical pixel, such as padding of 15 instead
  of 16, is not counted. Two pixels or more is.
- **What Chrome does that Flutter does not.** `lib/ui` does these where a picture needs them (each
  is in the widget's code with the number that shows it):
  - Chrome lays a `1.5px` border out as 1px (the pending badge is 20.25px tall, not 21.25).
  - Chrome puts half of a letter spacing before a glyph and half after it, and Skia places glyphs on
    a quarter of a device pixel, so a text with a letter spacing sits a hair under a quarter pixel
    further right in Flutter's picture (`letterSpacingShift`). Without it a 9.5px label differs by 5%.
  - Chrome rounds a font's ascent and descent to whole pixels and floors the half-leading, so a line
    of text inside a taller line box sits up to a pixel higher or lower than Flutter's
    (`cssBaselineShift`, `BlinkLine`).
  - CSS clips a box shadow inside the box, Flutter paints it under the whole box: a see-through box
    with an edge (the pending badge) uses `OutsideShadow`.
  - CSS paints the first shadow of a list on top, Flutter the last: the brand button's edge and glow
    are reversed.
  - A multi-word text is laid out word by word (`CssText`): Blink shapes each word and each space on
    its own and keeps every width in 64ths of a pixel, rounded up, so a line is a hundredth or two
    wider than Flutter shapes it, and every word after the first starts a hair further right. A
    hundredth decides which quarter of a device pixel a glyph is drawn on, so a flowed row of
    pills (the name shortcuts) drifts off the web's picture unless it is laid out the same way.
    Flutter also rounds a laid-out text's width up to a whole pixel; `CssText` uses the exact one.
  - Chrome rounds the left, top, right and bottom of every box to whole device pixels when it paints
    it, and keeps the fractions for layout and for the text inside. `SnappedDecoratedBox` (used by
    `PressSurface`) paints a box that way, and `snappedColumns` lays out equal columns (the keypad's
    102.67px keys) with their edges on whole pixels, the text staying where the unrounded box puts it.
    Without it every fractional edge is anti-aliased across two pixels and counts as a difference.
  - Chrome adds line boxes up as CSS gives them (19.5px for one line of 13px at 1.5), while Flutter rounds every
    line up to whole pixels (20px), so a screen of such lines drifts further from the web's with each one.
    `CssLines` takes the rounding back for the lines home is made of (the hero, a day's heading, a row's
    status line).
  - Chrome paints a box's edges, and an outline's, on whole device pixels wherever the page's fractional
    lines put them: the hero card, the budget bar and the focus ring use `SnappedDecoratedBox`.
  - A dashed border is each straight side on its own, dashes three widths long and gaps two, from where
    Chrome starts each side (`_DashedBorder`, the nudge card).
  - A `Container` insets its child by its border; a `DecoratedBox` does not (a 2px border is padding
    in the web's box model, so add it).
  - A box that holds another focusable (a transaction row and its badge) is focused while the one
    inside is, but only the one that has the primary focus rings. And a ring that comes and goes must not
    change the tree around its child (it would rebuild the child's state): `RingBox` keeps one tree.
  - A row's 44px badge sits in a 20px line (`-my-3`): `OutsetBox` takes the room back, and
    `HitTargetBoost` lets a touch on the part outside the line still reach the badge, as a browser does
    for an overflowing element.
- **Categories are managed from home's Categorías tab and the detail (founder ruling, Stage 3c).** There is no
  categories page, on the web or in the app. The tab has the Gastos | Ingresos switch, "Nueva categoría" and the
  archived ones folded at the end; the detail has "Editar" (the category sheet: name, kind, emoji, colour and
  "Archivar categoría") and, on an archived one, "Restaurar". There is no way to clear a budget: the web's sheet refuses
  zero and the API has no delete, so the app has none either. The pairs:
  - `home-budgets` (the tab, Gastos), `categories-income` and `categories-archived-open` (every income category
    archived, so the fold's row is in view), `category-new-sheet`, `category-edit-sheet` and `category-archive-sheet`
    (the question, with its count of recurring payments) and `category-detail-archived` (Casa, October's fixture).
    Their stories are `home-home--budgets`, `--categories-income`, `--categories-archived-open`, `--new-category-sheet`
    and `manage-categories--detail`, `--edit-category-sheet`, `--archive-sheet-open`, `--archived-detail`; the
    budget sheet's pairs (`budget-sheet`, `budget-sheet-negative`) are as they were.
  - `APP_GETS` has Casa's own movements as the app asks for them. The edit sheet asks the web's one page (200 rows) of
    the category's transactions, to say whether its kind is fixed.
  - **The archived note's dashes.** Blink's dashed border starts the bottom side's dashes in a different place for
    the detail's note than for the home nudge (the phase follows the card, which is not known), so the note passes
    `DashedBorderPainter.bottomPhase: 4`, measured on the web's picture.
  - **Text height.** A paragraph whose line is 22.5px (15px at 1.5: the confirm sheet's words, the budget card's "Sin
    presupuesto en…") is `CssLines`, as the other fractional lines are: without it every line is a half pixel taller
    than the web's and the sheet is 3px short at the top.
- **Search (`/search`, the web's `search-search--*`).** The app has the screen and tests it as widgets
  (`apps/mobile/test/search/search_screen_test.dart`, copy from the web's `search.*` messages, camelCase `search*` keys in the
  ARBs); there is no parity pair yet. Known differences: the magnifier in home's header is the web's second `.lk-avatar`
  (`home.search`, named "Buscar"); the field's 🔍 is inside the box (`WebTextField.leading`); the next page loads when
  the end of the page is near, where the web shows a "Ver más movimientos" button; a failure of the first search or of a
  page is a failure row with Reintentar (the web's alert), and the filters are not kept in the address.
- **Recurring payments (`manage-recurring--*`).** The page at `/recurring` and its sheets (new, edit, the delete question).
  The pairs are `recurring-list`, `recurring-empty`, `recurring-pesos`, `recurring-new-sheet`, `recurring-edit-sheet`,
  `recurring-delete-sheet`, `recurring-new-sheet-yearly` (day only) and the three "after a save" pictures
  (`recurring-yearly-saved`, `recurring-income-saved`, `recurring-deleted`).
  - A story that ends with a save or a delete holds the list the fake API answered *after* it, so the app renders that
    list from the fixture. The toast is gone by the time the web's picture is taken; the ring a script's click leaves on
    the add button is not, so the app test focuses it and sends a key (`_ringOnAdd`).
  - `NewSheetOpen`, `EditSheetOpen`, `DeleteSheetOpen` and `NewSheetYearly` were added to `Recurring.stories.tsx` to give
    the sheets a pair. (`DesktopDay` cannot be one: it looks for the desktop sidebar, so at 412px its play function throws
    and the shot is the page without the sheet.)
  - **The footer.** The form's footer is stuck (`StuckGaps.recurring`): the form's gap is `space-3`, so the figure sits 12px
    above the keypad (`AmountField.gap`), and the footer sits flush on the sheet's padding. Its two buttons stretch to the
    tallest, as the flex row does.
  - **The selects and the dates** are drawn as the web's fields but open the app's own pickers: a sheet of choices for the
    day and the month, and the date picker for the dates. The end date has a small button to take it out again, which the
    browser's own date control does by itself. The pictures stop above them (the sheet scrolls), so they carry no pair.
- **Análisis (`insights-insights--*`).** The page is as long as its three cards (about 2130px), and a pair
  compares the viewport only, so the stories that look at a card below the fold scroll the page to it
  (`TrendScrolled`, `TrendYearScrolled`, `TrendGapsScrolled` and `CostOfLivingScrolled` were added to
  `Insights.stories.tsx`; the card starts 16px under the top, or as near as the page's end lets it). The app test
  scrolls the app's own page to the same offset (`position.jumpTo`, or as far as it goes), so the gradient in those
  pictures is the one a phone shows.
  - The charts are Recharts on the web and a `CustomPainter` in the app (`lib/insights/chart_geometry.dart` is a port of
    what Recharts computes). `pnpm --filter @wambito/web parity:insights-geometry` reads what the web draws for the
    insights stories (sector paths, bars, grid, axis names, the budget line) into
    `apps/mobile/test/insights/recharts_geometry.json`, which `chart_geometry_test.dart` checks the port against, with the
    stories' own data.
  - Recharts leaves out the month names that would touch, measuring them in a hidden span under the `body` (Nunito
    11px at weight 700) while the names are drawn at 800: the app measures the same way (`measureTickName`).
  - Recharts keeps a bar out of the picture when it has no height; the stories' counts of bars are of the months
    that have data.
- **The entry screens (`signin-*`, `verify-*`, `code-input-*`, `passkey-offer-*`).** The sign-in screens, the magic
  link's failed and checking pages, the code boxes and the passkey offer are paired with
  `sign-in-signin--*`, `sign-in-verify--*`, `sign-in-codeinput--*` and `sign-in-passkeyoffer--*`. Each sits in a
  `ShellFrame` for Storybook's 16px (no bar under it). The pairs that differ from the stories as they were:
  - **Stories added for the pairs.** `Verify.stories.tsx` has `RejectedCode` and `NoConnection` (the failed page, which
    only `ExpiredDay` stopped at, and only by day in English). The sign-in stories are as they were: the code step has
    the web's 30 second wait before "Reenviar código", counted by the app's own clock (`clockProvider`, pinned like the
    story's), so its pairs show "Reenviar en 30 s".
  - **The email field's focus.** The app focuses it on opening (the person tapped "Entrar con mi correo", and a Stage
    3 test pins it); the web leaves it alone so the keyboard does not cover Wambi. The pairs put the focus down
    (`_putFocusDown`) where the story has none.
  - **"Usar passkey" is "Entrar con huella" in the pairs** (`EmailScreen.passkeyLabel`), as the detail's "Editar" is
    in the budget pairs: the email screen's button keeps Stage 3's words and the web's sign-in has the others.
  - **"Probar sin correo" is in no pair.** It sits on the first screen, which the web has no story for (its sign-in
    has no guest and no first screen with three ways in), so the entry screen, "Guarda tu progreso" and the magic
    link that finds a guest signed in have their own goldens in `test/entry/goldens`, to review by eye
    (`test/entry/entry_golden_test.dart`).
  - **The code is one text field with six boxes drawn over it**, where the web has six inputs. The ring is on the
    next box to type, and on the last once the code is whole. The web's box keeps a typed digit selected when focus
    moves to it, and a pasted code not; the boxes do the same (a change of two digits or more is a paste), in the
    browser's selection colours (`#1E5172` at night, `#A1D2F5` by day, the digit black), the highlight as wide as
    the glyph and as tall as the font's rounded ascent and descent.
  - **A click's focus ring.** `PasskeyFailed` and the offer's `Failed` leave the focus, with a ring, on the button that
    was clicked; the app's tests focus it and press a key. `NoConnection` blurs it (a finger rings nothing).
  - **The magic link's `AsksFirst` and `OffersTheApp` have no pair.** The app signs the link in at once (Stage 3: a
    link opened in the app is already the person's choice), so its "checking" page is the web's `Checking`, with the
    same words.
  - **The passkey offer** is wired as the web wires it (`use-finish-sign-in.ts`, `shouldOfferPasskey`): right after an
    email sign-in (the code or the magic link, never a passkey sign-in, a claim or a guest), when the phone can use
    passkeys, the account has none (`GET /api/auth/passkey/list-user-passkeys`) and it has not answered on this phone.
    The answer is kept per account on the phone (`passkey.offered`, as the web keeps `wambito.passkey.offered` in
    `localStorage`). Its pairs are the stories' `Offer`, `OfferDayEnglish`, `WaitingForTheFingerprint` and `Failed`.
- **Settings (`settings-*`).** The web's Settings has six cards, and the app draws them all as the web does (Preferencias,
  "Hora y moneda", the passkeys, "Tus datos" with its import link to the app's own page and the export's two buttons, "Comentarios
  e ideas" with its button that writes to the founder, and the danger-bordered card that deletes the account). The app's `SettingsScreen(webSectionsOnly: true)` draws what the stories leave on the page: no "Automático"
  language (the web has two languages; the app's third follows the phone) and none of the app's own cards.
  - **Stories.** `manage-settings--app-sections`, `--app-sections-day-english` and `--app-sections-sound-off` are the page from
    the top. The stories that look at a card further down scroll the page to it (`--app-sections-currency-open`, its options 16px
    under the top; `--app-sections-passkeys` and `--app-sections-data`, which the page's end stops at); the sheets are
    `--time-zone-sheet-open` (a country searched), `--time-zone-sheet-current` ("Actual"), `--time-zone-no-match` and
    `--passkey-remove-sheet-open`. The delete card is `--app-sections-delete` (the page's end), and its sheet is
    `--delete-sheet-open`, `--delete-sheet-ready` (the email typed in capitals, the button on), `--delete-sheet-failed` (a
    refused delete: the reason under the field, the focus nowhere: the story lets go of it) and
    `--delete-sheet-day-english`. The export has no story of its own: its buttons are in `--app-sections-data`; "Comentarios e ideas" is `--app-sections-feedback`. What
    follows a tap there is the app's own (a sheet that asks to save or share the file, since a phone has no download folder to
    drop it in), so it has no pair; the widget tests cover it (`test/settings/export_test.dart`).
  - **Scrolling.** The app's test scrolls as the story did, to a whole pixel (Chrome scrolls to whole pixels); a page that ends
    on a half pixel is rounded up by Chrome (0.5px more scroll), which the test gives the frame (`_page(roundedUp: true)`). The
    story that clicks a button below the fold scrolls the browser to centre it: the test centres it too.
  - **Passkeys** are the story's in-memory list (the web's `storyPasskeys`), not an API answer: the test hands the app the same
    list (`SettingsPasskeys`). "Este navegador no permite crear huellas" is "Este teléfono…" in the app, so that story has no pair.
  - **The search field** is `type="search"`: Chrome draws its blue clear button while there is text, which the app does not.
  - **Lines in a taller box.** A 13px or 15px line in a CSS line box (19.5 and 22.5px) is `CssLines`, with its baseline where Blink
    puts it (`CssBlinkLines`); the card titles (`SettingsSection`) carry the same shift, which they lacked (a pixel too low).
  - **The app's own cards** (the guest's "Guarda tu progreso", "En este teléfono": vibration, the two notices and the widget; the
    voice models, the server, "Más en la web", About, signing out) are drawn with the web's parts and have goldens of their own in
    `test/settings/goldens` to review by eye, with the sheets the guest's dialogs and the server's address became.
  - **Copy.** The theme's third choice is the web's "Automático"; the sound hint is the web's, and when the vibration is off the
    English one says "Vibration stays off." where the web's says "stays on".
  - **Weights.** The web loads Nunito from 600 up, so a `font-normal` text (the switch's hint) is drawn at 600 by Chrome; the app
    does the same (`SettingSwitch`).
  - **Paragraphs** are broken as Blink breaks them (`CssParagraph`): a line that is exactly as wide as its column breaks in a
    different place when its words are measured whole, as Flutter does.
  - **Day pairs** sit at 1.8–2.2% of ink: the text is placed to the pixel, and what is left is how Chrome and Flutter draw the same
    glyphs (Flutter's dark-on-light text is a little heavier). The two pictures that show the most text at once
    (`settings-currency-open` and `-passkeys`, by day) carry `maxInk: 2.3` in parity.json, which gives
    that pair that much room (compose never uses it to lower the limit, prints it on the pair's line, and refuses any `maxInk` over 2.5%: a pair that needs more is wrong, not noisy); the picture is
    still looked at first.
  - **Delete card.** `.lk-danger-zone` is a 2px border of the danger colour over the stroke's (55/45), inside the card
    (`border-box`: the padding stays, the content is 2px narrower). The input's `aria-invalid` has no style on the web, so the
    field keeps its border when the delete is refused.
- **The confirm sheet (`confirm-sheet-open*`).** `ui-confirmsheet--*` were added (the web had no story of it). A `flex-1`
  button is its own padding and border and an equal share of what is left, so "Cancelar" (8px a side) is narrower than
  the action (24px and a 2px border): `flexOneRow`. The guest's questions (`ChoiceSheet`: sign out, change server, the
  claim offer, signing in over a guest) are this sheet with a second way forward; the web has no guests.
- **The celebration (`celebration-*`).** The shots take animations at their end, where a celebration is gone, so
  `feedback-celebration--mid-flight*` stop the live one part of the way through (`freezeAt`: every animation paused at
  that fraction of one `--celebrate`, its look kept as plain styles, the stay made an hour long first) and the app is
  stopped at the same moment (`parityGolden(settleAfterAct: false)` and a pump of that long once the celebration and
  Wambi's sprite have started). The pairs: half way above the spot, clear of the toast, with no spot, a tenth in, by day in
  English at three quarters, and under reduced motion. The 28 pieces are the web's (`confettiBurst`), the easings are its
  keyframes' (`confettiAt`, `wambiAt`).
  - Under reduced motion the controller must not take the system's shortened durations (`AnimationBehavior.preserve`): the
    web still fades him over the same stay.
  - The sprite's loops are the web's (`WambiSprite.loopMs`: wave 1200, worried 2000, celebrate 1000 ms) and the
    celebration's plays for the whole stay (`WambiFace.endless`).
- **Toasts** are the web's `ToastHost` everywhere now (above the Navigator, in `WambitoApp`): the Material snackbar is gone
  (`lib/home/toast.dart`). The shell lifts them 92px above its bottom bar. `animateBar: false` (tests only; the app's
  `toastBarAnimatesProvider`) stops the time bar, which asks for a frame all the way to the end of the toast, so a test that
  settles the frames would wait the toast out.
- **Stories that are not pictures of the component.** A few stories' end states are not what the
  component draws on its own:
  - `ui-toast--*`: Playwright takes the picture with CSS animations at their end, so the time bar is
    gone and the toast is still there. The app's host here lives for an hour (`dismissAfter`) while its
    bar runs its real eight seconds.
  - `ui-bottombar--*`: the web has no 🎤, so the pairs hide it (`showMic: false`);
    `test/ui/bottom_bar_golden_test.dart` has its own pictures of the bar with the 🎤, to review by eye.
  - Quick capture and the voice download have no web story, so no pair: `test/capture/capture_golden_test.dart`
    has pictures of the listening, the preview, a card open, an unread fragment, the download offer and the
    download under way, in night and day, to review by eye (`test/capture/goldens`).
  - `ui-namefield--two-rows-at-most` has no pair: `useRowLimit` measures before the fonts have loaded,
    so the story shows six shortcuts where the fonts' widths show seven.
  - A story's click leaves the focus on what it clicked, which Chrome rings; `act:` presses Tab to the
    same control.
- **Pictures are the Mac's.** Text and shadows rasterise differently on Linux. The parity goldens
  are tagged `golden`, so CI skips them (`dart_test.yaml`), as it skips the other goldens.
