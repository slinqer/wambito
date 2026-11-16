Wambito is a personal-finance app: **your budget, and you'll actually enjoy looking after it** (es: *Wambito es tu presupuesto, y te va a dar gusto cuidarlo.*). It is free forever and open source. The look, **Arcade**, is playful (the product is never called a game): a deep purple night sky (or a lavender day sky), candy-bright status colors, chunky rounded type, and surfaces that sit on a solid bottom edge and **press down** when touched. Wambi, a 3D gold coin, is the mascot and reacts to how the month is going.

Use this system for the landing page, the web app and the mobile app (Android and iOS). Every value lives in `tokens.json`; component classes live in `components/bundle.css` (prefix `lk-`).

## Content fundamentals

- **Spanish is the default language, English the second.** Write Spanish first, then translate; never ship one without the other. Address the person as **tú** (`te quedan`, `te pasaste`), never usted.
- **Positioning:** Wambito is your budget, and looking after it feels good. Playful, never a game: don't call it one ("un juego", "feels like a game"), even though the interface is arcade-bright.
- **Free forever, open source, and honest about it.** Never imply a later payment (no "Empieza gratis", no "free trial") and never mention or promise a business model. Claim only what exists: imports come "from other apps" (Budge today; others "soon"), the mobile app is Android and iOS ("soon"). Privacy copy says only what is true: data is end-to-end encrypted on the person's device (Wambito launches with it; not even Wambito can read it), is never sold or shared with advertisers, can be exported or deleted, and the open code lets anyone check how; no "can't leak", "we can't see" or at-rest encryption claims.
- **Talk about money the way friends do.** "Lukas" means money in Colombia; use the slang in brand moments ("Tus lukas, por fin claras."), not in every label. Labels stay plain: `Supermercado`, `Agregar gasto`, `Presupuestos`.
- **Say what happened with the number in it.** Status lines are sentences with the amount: `Quedan 46,33 €`, `Te pasaste 14,12 €`. Never a bare percentage, never a negative percentage.
- **Wambi speaks in short, warm, specific lines**, generated from rules with the real figures: `¡Vas bien! Te quedan 11 días y aún tienes margen.` · `Ojo: ya te pasaste 20,20 € en Supermercado.` · `¡Anotado!`. One sentence, at most one exclamation, no guilt.
- **Buttons say the action**, uppercase in the display face: `AGREGAR GASTO`, `GUARDAR`, `EMPIEZA AHORA`. Toast actions are verbs in sentence case: `Deshacer`, `Ponerle nombre`.
- **Casing:** sentence case everywhere except button labels and `overline` labels (uppercase).
- **Emoji:** only as category glyphs inside a `lk-tile` (🛒 🍽️ 🏠 🚗 ⭐ ☂️) and as the celebration sparkle. Never in running text or headings.
- **Money format** follows the locale with `Intl.NumberFormat`: `562,92 €` (es), `€562.92` (en). Expenses carry a real minus sign `−6,08 €`.

## Visual foundations

### Color
- The screen background is never flat: `radial-gradient(120% 60% at 50% 0%, bg-glow, bg 55%)` (class `lk-screen`).
- Cards sit on `surface` (hero, sheets, toasts) or `surface-row` (lists); wells and tracks use `surface-sunken`.
- Text is `ink`; secondary text `ink-muted`. Both pass AA on every surface in both themes.
- **One hero figure per screen** in `good` (what is left). Status uses `good` / `near` / `over` and is **always** paired with words, so it never depends on color alone.
- `brand` is for actions only: primary buttons, the ＋ button, selected states, links in toasts. White text on it via `on-brand`.
- `gold` and `candy` are celebration and identity colors (Wambi, the wordmark gradient, confetti). Never under text, with one landing-only exception: the **marker highlight** on the hero headline's key word ("lukas" / "money"), a solid `gold` blob with an irregular radius and a slight tilt, its text in `on-gold` (dark ink, 14.6:1 night, 11.1:1 day). The handwritten annotation sits on a translucent `candy` stroke (about 32 %) with its text in `ink` (6:1 or more in both themes).
- **Themes:** `night` is primary; `day` is the same identity on lavender. The app follows the system setting by default and the person can force either in settings.

### Type
- **Fredoka** (`display`) for figures, titles and buttons; **Nunito** (`text`) for everything else, set heavy (700–900). Both from Google Fonts (self-hosted in the app through Fontsource).
- **Caveat** (`hand`) is a third family for short handwritten annotations on the landing only (style `annotation`, 700, tilted about −4° on a marker stroke), never UI text. Real text, so screen readers and translations get it.
- Styles: `amount-hero` for the one big number, `title`, `heading`, `amount-row` for list amounts, `button`, `logo`; then `body`, `label`, `caption`, `overline`; and `annotation` (landing only).
- Figures are tabular (`font-variant-numeric: tabular-nums`) wherever amounts line up.

### Shape and depth
- Big radii: `radius-xl` for the hero, sheets and primary buttons; `radius-lg` for rows; `radius-md` for controls; `radius-pill` for badges and bars.
- **Depth is a solid bottom edge, not a blur:** `edge-sm` for rows and chips, `edge-md` for the hero and keys, `edge-brand` for primary buttons. Pressing moves the element down by its edge height and collapses the edge (`lk-press`, `.is-pressed`). Every tappable thing presses; nothing that isn't tappable has an edge.
- Rows and cards add a 2px `stroke` border.

### Motion and feedback
- Feedback is **semantic**: `tap`, `expenseSaved`, `incomeSaved`, `paid`, `nearLimit`, `overBudget`, `undo`. Each event combines animation, a short sound (mutable) and vibration where the platform allows it (Android; not iOS Safari).
- Timings: `press` 80ms, `sheet` 260ms, `count-up` 700ms for the hero amount after a save, `celebrate` 1200ms for the ¡Anotado! moment.
- Under `prefers-reduced-motion` keep fades only and show Wambi as a still image.

### Focus and accessibility
- Focus ring: 3px solid `focus` with a 2px offset on every pressable (`:focus-visible`).
- Touch targets are at least 44px. Contrast is AA in both themes; the token notes give the ratios.

### Layout
- Phone first. Side gutter `space-4`, gaps between rows `space-2`, between sections `space-5`.
- App navigation: bottom bar **Inicio · ＋ · Análisis** with the raised ＋ in the middle; on desktop it becomes a left sidebar.
- Home is one hero card, then a **segmented control (Presupuestos ⇄ Movimientos)** and the list. Adding a transaction is a bottom sheet: amount first, category chips, an optional name with recent shortcuts.

## Wambi, the mascot

- A chubby 3D gold coin with a ridged edge, big eyes, rosy cheeks, dark purple arms and legs and pink sneakers. Concept art: the `Mascot` asset group.
- Three moods mirror the budget: **happy** (every category ok, or right after logging), **worried** (a category is near or over its limit; sweat drop), **celebrating** (a save, a pending payment marked paid, a month closed within budget). Each mood has its own hand-made sprite sheet (4×2 frames): happy waves, worried wrings his hands and sweats, celebrating jumps with fists up among sparkles. Under reduced motion each shows one still frame.
- On the landing page Wambi is drawn in 2.5D: his sprite sheets with CSS depth on top (a soft ground shadow, an idle bob, a slight tilt toward the cursor on desktop, a hop on hover or tap). He rolls in once per visit, waves from the hero, then stands beside each section's heading in that section's mood (worried next to "how it works", celebrating by the final call to action), turning edge-on like a coin to move between spots so he never passes over text. In the app he is a lightweight 2D rendering beside a speech bubble (`lk-bubble`). A 3D model was tried and kept only as an experiment.
- Never put Wambi on top of figures or text, never recolor him, and never show him angry or shaming.

## Iconography

- Emoji are for categories only: category glyphs are emoji inside a 34px `lk-tile` (44px `lk-chip-tile` in the picker) on a tinted ground. They read on both themes and need no icon font.
- Interface icons live in `icons/icons.json`: SVG path data on a 48 grid in `currentColor`, read by the web's `Icon` (`apps/web/app/ui/Icon.tsx`) and copied for the phone's `LkIcon` (`apps/mobile/lib/ui/lk_icon_shapes.dart`, checked against the JSON by `test/ui/lk_icon_test.dart`). Our own are thick round strokes (5–8 units, round caps and joins): search, user, plus, close, the two chevrons, mic, check, cloud-off. Home and chart are Plump Free by Streamline (CC BY 4.0, credited in the phone's About and the root README).
- The bottom bar's current tab shows its icon `filled` and its label in `ink`; the others `outline` in `ink-muted`. Every other icon is `filled`. No gold on the tabs.
- Add an icon in the JSON first (draw it in the same strokes), then in the Dart copy.
- There is no logo mark yet: the wordmark is the word **Wambito** in `logo` style with the gold → candy gradient. It stays on the sign-in, onboarding and the desktop sidebar; home's header has none (the month and two icon buttons on one row).
