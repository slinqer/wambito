# Settings by Category Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one long Settings page (phone and web) with a one-screen menu of six
categories, each opening its own light screen of icon rows, with "Mis agentes" first.

**Architecture:** A pure "which categories, in which order" model per platform feeds a menu screen;
each category is its own route (`/settings/<id>` on the phone, `/app/settings/<id>` and
`/demo/settings/<id>` on the web). Two shared building blocks per platform (a group and a row) draw
every category screen; the existing sections' logic (passkeys, security, assistants, time and
money, export, feedback, server, auto-capture) is reused, only their presentation changes. New
interface icons go through the shared `icons.json`; brand logos through a new shared
`brands.json`, both with a Dart copy checked by a test.

**Tech Stack:** Flutter (go_router, Riverpod, flutter_test, golden parity tests), React Router 7 +
React, use-intl, Vitest, Storybook, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-22-settings-categories-design.md` (read it first). The
approved mockups: `docs/superpowers/specs/2026-11-22-settings-categories-mockups/index.html`
(open in a browser); the chosen icon and logo SVGs are in its `icons/` and `logos/`.

## Global Constraints

- Branch from `origin/main` (after `797ae6de`), never from an older checkout.
- Six categories, in this order: `agents` "Mis agentes", `account` "Cuenta y seguridad",
  `preferences` "Preferencias", `capture` "Captura" (phone only), `data` "Tus datos", `more` "Más".
- The menu fits one 360 x 740 dp phone screen at font scale 100 % without scrolling.
- "Mis agentes" row: the same 40 px `surface-sunken` tile as the others, its icon the four logos
  (ChatGPT, Claude, Lumo+, Grok) two by two in `brand`; line "ChatGPT · Claude · Lumo+ · Grok".
- Logos are one colour (`currentColor`) everywhere except the connect sheet's handshake scene.
- App names are never translated: ChatGPT, Claude, Lumo+, Grok, Revolut, Google Wallet.
- Every new string in es, en, it, pt, on both platforms where the screen exists.
- No setting is added or removed; every long explanation moves into the sheet or flow its row opens.
- "Cerrar sesión" stays under the phone menu; under it, centred and muted, "Wambito <version>"
  from `appVersionProvider` (`apps/mobile/lib/settings/feedback.dart`).
- No API or MCP change, so no `CHANGELOG.md` line.
- Write the failing test first. Conventional Commits, `feat(mobile): …`, `feat(web): …`; stage by
  path; no `Co-Authored-By` line.
- Generated files are regenerated, never hand-edited (root `AGENTS.md`).

## Review Focus

- A grant whose client is none of the four apps (another MCP client): it must still be listed in
  "Mis agentes" with a generic icon and be revocable. Test in Task 9 and Task 10.
- An encrypted (`preview`) account: Tus dispositivos and Clave de recuperación show; "Importar"
  shows the "Próximamente" chip. A plain account shows neither security row. Tests in Tasks 5, 11,
  12, 14.
- A guest (no email): "Mis agentes" shows why an email is needed first, no "Conectar"; the
  "Guarda tu progreso" / "Protege tus datos" block sits above the menu, never inside a category.
  Tests in Tasks 7, 8, 9, 10.
- Coming back from the AI app after "Conectar": the list is fetched again (phone resume, web tab
  focus) and a new grant raises "<app> quedó conectado." once, not on every return. Tests in
  Tasks 9 and 10.
- Italian and Portuguese at the phone's 130 % font: menu lines and value rows truncate with an
  ellipsis on one line, never wrap the row taller than 76 px. Tests in Tasks 6 and 8.

---

### Task 1: Commit the approved design and assets

**Files:**
- Add: `docs/superpowers/specs/2026-11-22-settings-categories-design.md`
- Add: `docs/superpowers/specs/2026-11-22-settings-categories-mockups/**`
- Add: `docs/brand/wambi-handshake-{claude,chatgpt,lumo,grok}.png`
- Add: `docs/superpowers/plans/2026-11-22-settings-categories.md`

- [ ] **Step 1:** In the new worktree, copy these files from the founder's main checkout if they
  are not on the branch yet (they were written there, uncommitted).
- [ ] **Step 2:** `scripts/check-old-name.sh` passes (the mockups contain the slang "lukas" in an
  example; if the guard flags `index.html`, add it to `.github/name-allowlist.txt` with reason
  `money`).
- [ ] **Step 3: Commit** `docs: settings by category, design, mockups and handshake scenes`.

### Task 2: New interface icons in icons.json and its Dart copy

**Files:**
- Modify: `docs/design/system/project/icons/icons.json`
- Modify: `apps/mobile/lib/ui/lk_icon_shapes.dart`
- Modify: `apps/web/app/ui/icon-shapes.ts` (only if `IconName` is a hand-written union)
- Modify: the About licences list (phone `apps/mobile/lib/settings/licenses.dart`, web About page)
- Test: `apps/mobile/test/ui/lk_icon_test.dart` (exists; must keep passing), a web test that
  every `IconName` renders (`apps/web/app/ui/Icon.test.tsx`, create if missing)

**Interfaces:**
- Produces: icon ids `shield`, `sliders`, `bell`, `folder`, `info`, `fingerprint`, `phone`,
  `laptop`, `key`, `trash`, `wand`, `calendar`, `widget`, `eye-off`, `globe`, `moon`, `volume`,
  `clock`, `coin`, `upload`, `download`, `server`, `map`, `chat`; Dart `LkIconName.shield`, …,
  `LkIconName.eyeOff`, `LkIconName.chat`.

Source SVG for each (in the mockups' `icons/`): shield Shield-1, sliders
Horizontal-Slider-Square, bell Ringing-Bell-Notification, folder File-Folder, info
Information-Circle, fingerprint Fingerprint-2, phone Phone-Vibrate, laptop Laptop, key Padlock-Key,
trash Recycle-Bin-2, wand Magic-Wand-1, calendar Calendar-Mark, widget Widget, eye-off Invisible-1,
globe Earth-1, moon Moon-Stars, volume Volume-Level-High, clock Circle-Clock, coin Dollar-Coin,
upload Upload-Box-1, download Download-Box-2, server Database-Server-3, map Map-Fold, chat
Chat-Bubble-Oval-Smiley-1. All are 48-grid filled paths: each `<path>` becomes
`{ "d": …, "fill": true, "evenOdd": true }` when it has `fill-rule="evenodd"`.

- [ ] **Step 1:** Add `"settings icons render"` web test: for each new id, `render(<Icon name={id} />)`
  has `svg[data-icon=id] path` count ≥ 1. Run `pnpm --filter @wambito/web test Icon` → FAIL.
- [ ] **Step 2:** Add the 24 entries to `icons.json` (same `filled` shape list as the others; no
  `outline` variant) and update its `$comment` credit: "… and the settings icons are Plump Solid
  Free by Streamline, CC BY 4.0".
- [ ] **Step 3:** Add the 24 `LkIconName` values and their shapes to `lk_icon_shapes.dart`,
  extend its header credit the same way, and add Plump Solid Free to both About licence lists.
- [ ] **Step 4:** Run `pnpm --filter @wambito/web test Icon` and `flutter test test/ui/lk_icon_test.dart`
  (in `apps/mobile`) → PASS.
- [ ] **Step 5: Commit** `feat(design): settings icons from plump solid free`.

### Task 3: Brand logos, one colour, shared

**Files:**
- Create: `docs/design/system/project/icons/brands.json`
- Create: `apps/web/app/ui/BrandLogo.tsx`
- Create: `apps/mobile/lib/ui/lk_brand_logo.dart`
- Test: `apps/web/app/ui/BrandLogo.test.tsx`, `apps/mobile/test/ui/lk_brand_logo_test.dart`

**Interfaces:**
- Produces (web): `type BrandName = "chatgpt" | "claude" | "lumo" | "grok" | "revolut" | "google-wallet"`;
  `<BrandLogo name={BrandName} size?={number} className? />` (an `aria-hidden` svg in
  `currentColor`, `data-brand={name}`).
- Produces (phone): `enum LkBrand { chatgpt, claude, lumo, grok, revolut, googleWallet }` with
  `id` like `LkIconName`; `LkBrandLogo(LkBrand brand, {double size = 22, Color? color})`.

`brands.json`: `{ "$comment": <sources and licences>, "logos": { "<id>": { "viewBox": "<minx miny w h>", "paths": [{ "d", "evenOdd"? }] } } }`.
Sources (mockups' `logos/`): chatgpt Openai-Logo (Streamline Logos Solid Free), claude
Claude-Code-Ai-Logo (same set), grok Grok-Ai-Logo (same set), lumo `Lumo-mono.svg` (Proton's
`lumo-2-icon.svg` with its white details as cut-outs: carry its mask into `evenOdd` paths, or keep
the mask shape list as `{ "d", "cut": true }` entries drawn as a clip), revolut
Revolut--Streamline-Simple-Icons (CC0), google-wallet Google-Wallet--Streamline-Font-Awesome
(Font Awesome Free, CC BY 4.0).

- [ ] **Step 1:** Write `BrandLogo.test.tsx`: each name renders `svg[data-brand=name]` with the
  viewBox from `brands.json` and every path `fill="currentColor"`. Write
  `lk_brand_logo_test.dart` modelled on `lk_icon_test.dart`: the Dart copy equals `brands.json`.
  Run both → FAIL.
- [ ] **Step 2:** Create `brands.json`, `BrandLogo.tsx` (reads the JSON) and `lk_brand_logo.dart`
  (a Dart copy + widget using `svg_path.dart`). Add the four licences to both About lists.
- [ ] **Step 3:** Run both tests → PASS.
- [ ] **Step 4: Commit** `feat(design): one-colour brand logos for agents and payment apps`.

### Task 4: Handshake scenes in both apps

**Files:**
- Create: `apps/web/public/wambi/handshake-{claude,chatgpt,lumo,grok}.webp`
- Create: `apps/mobile/assets/wambi/handshake-{claude,chatgpt,lumo,grok}.webp`
- Modify: `docs/AGENTS.md` (the Wambi scenes rule: name these four as the exception that shows the
  app's logo, founder's decision 2026-11-22)

- [ ] **Step 1:** From each `docs/brand/wambi-handshake-<app>.png`, cut the white background
  (corner flood-fill at 2.5 % fuzz for lumo, 8 % for the others, plus the bottom-centre point),
  trim, then `magick … -resize 512x512 -quality 90 -define webp:alpha-quality=100` into both
  folders, byte-identical. Check each on night `#241f48` and day `#ffffff` by eye: no white halo,
  the Lumo tile's edge intact.
- [ ] **Step 2:** If `apps/mobile/pubspec.yaml` lists assets one by one, add the four.
- [ ] **Step 3: Commit** `feat(brand): wambi's handshake scenes for the four agents`.

### Task 5: The category model, both platforms

**Files:**
- Create: `apps/web/app/features/settings/settings-categories.ts`
- Create: `apps/mobile/lib/settings/settings_categories.dart`
- Test: `apps/web/app/features/settings/settings-categories.test.ts`,
  `apps/mobile/test/settings/settings_categories_test.dart`

**Interfaces:**
- Produces (web): `type SettingsCategory = "agents" | "account" | "preferences" | "data" | "more"`;
  `settingsCategories(): SettingsCategory[]` (the web has no capture);
  `isSettingsCategory(x: string): x is SettingsCategory`.
- Produces (phone): `enum SettingsCategory { agents, account, preferences, capture, data, more }`
  with `String get path` (`'/settings/agents'`, …);
  `List<SettingsCategory> settingsCategories({required bool webSectionsOnly})` (drops `capture`
  when `webSectionsOnly`).

- [ ] **Step 1:** Tests: the phone order is exactly
  `[agents, account, preferences, capture, data, more]`; with `webSectionsOnly` it is the web's
  `[agents, account, preferences, data, more]`; web `isSettingsCategory("capture") === false`.
  Run → FAIL.
- [ ] **Step 2:** Implement. Run → PASS.
- [ ] **Step 3: Commit** `feat(settings): the six settings categories`.

### Task 6: Light group and row building blocks

**Files:**
- Modify: `apps/web/app/features/settings/parts.tsx`, `apps/mobile/lib/settings/settings_parts.dart`
- Create: `apps/web/app/features/settings/SettingsRows.stories.tsx`
- Test: `apps/web/app/features/settings/parts.test.tsx`, `apps/mobile/test/settings/settings_rows_test.dart`

**Interfaces:**
- Produces (web): `<SettingsGroup label?={string}>{rows}</SettingsGroup>`;
  `<SettingsRow icon={ReactNode} title={string} line?={string} trailing={Trailing} onPress?={() => void} href?={string} />`
  with `type Trailing = { kind: "chevron"; value?: ReactNode } | { kind: "switch"; checked: boolean; onChange(v: boolean): void } | { kind: "chip"; text: string } | { kind: "trash"; label: string; onPress(): void } | { kind: "none" }`;
  `tone?: "danger"` colours title and icon `over`.
- Produces (phone): `SettingsGroup({String? label, required List<Widget> rows})`;
  `SettingsRow({required Widget icon, required String title, String? line, required RowTrailing trailing, VoidCallback? onTap, bool danger = false})`
  with sealed `RowTrailing`: `RowChevron({String? value})`, `RowSwitch({required bool value, required ValueChanged<bool> onChanged})`,
  `RowChip(String text)`, `RowTrash({required String label, required VoidCallback onTap})`, `RowNone()`.

Look (mockups): group on `surface-row`, 2 px `stroke`, `radius-lg`, `edge-sm`, padding 10/12; label
11.5 px 900 uppercase `ink-muted`; rows divided by a 2 px `stroke` line, none above the first; row
icon 20 px `ink-muted` in a 32 px box; title 14 px 800; line 12.5 px `ink-muted`, one line,
ellipsis; value 13 px 800 `ink-muted`; trash a 36 px `surface-sunken` square, icon `over`. A
switch row is one control (the whole row toggles), as `SettingSwitch` today.

- [ ] **Step 1:** Tests: a switch row is one `switch` role named by its title and toggles on tap;
  a chevron row with `value="Español"` shows the value; a trash row is a button named by its
  `label`; a danger row's title has the `over` colour; at 130 % text scale and an Italian
  40-character line, the row stays one line tall (`find.byType(SettingsRow)` height ≤ 76).
  Run → FAIL.
- [ ] **Step 2:** Implement both, plus stories for each trailing kind, night and day.
- [ ] **Step 3:** Run tests → PASS. **Commit** `feat(settings): light group and row parts`.

### Task 7: Web routes and the menu

**Files:**
- Modify: `apps/web/app/routes.ts`; Modify: `apps/web/app/routes/app.settings.tsx`
- Create: `apps/web/app/routes/app.settings._index.tsx`, `apps/web/app/routes/app.settings.$category.tsx`
- Create: `apps/web/app/features/settings/SettingsMenu.tsx`, `SettingsMenu.stories.tsx`
- Modify: `apps/web/app/features/settings/Settings.tsx` (becomes the category screen switch)
- Modify: `apps/web/app/i18n/messages/app.{es,en,it,pt}.json` (`settings.menu.*`)
- Test: `apps/web/e2e/settings.spec.ts`

**Interfaces:**
- Consumes: `settingsCategories`, `isSettingsCategory` (Task 5); `SettingsGroup`/`SettingsRow`
  (Task 6); `BrandLogo` (Task 3); `Icon` ids (Task 2).
- Produces: `<SettingsMenu />`; `<SettingsCategoryScreen category={SettingsCategory} />` exported
  from `Settings.tsx`; message keys `settings.menu.{agents,account,preferences,data,more}.{title,line}`.

Routes: under `app`, `route("settings", "routes/app.settings.tsx", [index(…_index.tsx), route(":category", …$category.tsx)])`,
and the same under `demo` with ids `demo-settings`, `demo-settings-index`, `demo-settings-category`.
An unknown `:category` renders the app's not-found. Each category page has a back link to
`/app/settings` (or `/demo/settings`). Menu lines (es): agents "ChatGPT · Claude · Lumo+ · Grok",
account "Passkeys, dispositivos, clave", preferences "<language> · <theme> · <currency>" (live
values), data "Importar, exportar", more "Comentarios". The protect / add-email block renders above
the menu rows. The web shows no version line and no sign-out here.

- [ ] **Step 1:** e2e tests: "settings opens on the menu of five categories, each with its line";
  "each category opens on its own URL and back returns to the menu"; "a reload on
  /app/settings/preferences stays there"; the existing language, theme, passkey, delete and export
  tests now navigate through their category first. Run against the dev stack → FAIL.
- [ ] **Step 2:** Implement the routes, `SettingsMenu` and the category switch (move today's cards
  under their category for now; Tasks 9, 11, 13 redraw them).
- [ ] **Step 3:** `pnpm --filter @wambito/web typecheck`, unit tests, e2e → PASS.
- [ ] **Step 4: Commit** `feat(web): settings menu and a page per category`.

### Task 8: Phone routes and the menu

**Files:**
- Modify: `apps/mobile/lib/router.dart`
- Create: `apps/mobile/lib/settings/settings_menu.dart`
- Create: `apps/mobile/lib/settings/category_screen.dart` (the shared `ManagePage` frame with back)
- Modify: `apps/mobile/lib/settings/settings_screen.dart` (split; the menu replaces the long page)
- Modify: `apps/mobile/lib/settings/security/signin_notice.dart` (push `/settings/account`)
- Modify: `apps/mobile/lib/l10n/app_{es,en,it,pt}.arb`
- Test: `apps/mobile/test/settings/settings_menu_test.dart`, `apps/mobile/integration_test/settings_test.dart`

**Interfaces:**
- Consumes: Tasks 2, 3, 5, 6; `appVersionProvider`.
- Produces: `SettingsMenu({bool webSectionsOnly = false})`;
  `SettingsCategoryPage({required SettingsCategory category, required List<Widget> children})`;
  routes `/settings/agents|account|preferences|capture|data|more`; arb keys
  `settingsMenuAgents`, `settingsMenuAgentsLine`, … `settingsMenuMoreLine`, `settingsVersion`
  ("Wambito {version}").

Menu lines (es): agents "ChatGPT · Claude · Lumo+ · Grok", account "Passkeys, dispositivos,
clave", preferences live "<language> · <theme> · <currency>", capture "Automática, voz, avisos",
data "Importar, exportar", more "Comentarios, servidor, acerca de". The provisional (offline first
run) page keeps today's behaviour: no menu, only Preferencias' content.

- [ ] **Step 1:** Widget tests: six rows in order with their lines; tapping each pushes its path;
  "Cerrar sesión" then "Wambito 1.0.4" (fake `appVersionProvider`) under the rows; at 360 x 740 dp
  the last row and the version are visible without scrolling; a guest sees "Guarda tu progreso"
  above the first row; `webSectionsOnly` hides Captura. Run → FAIL.
- [ ] **Step 2:** Implement; move today's cards under their category screens for now.
- [ ] **Step 3:** `flutter test` (without goldens) → PASS. **Commit** `feat(mobile): settings menu and a screen per category`.

### Task 9: Mis agentes, web

**Files:**
- Create: `apps/web/app/features/assistants/agents.ts`
- Modify: `apps/web/app/features/assistants/AssistantsSection.tsx` (becomes `AgentsScreen`)
- Create: `apps/web/app/features/assistants/ConnectAgentSheet.tsx`
- Modify: `apps/web/app/i18n/messages/app.*.json` (`settings.agents.*`; replace the old ChatGPT path)
- Test: `apps/web/app/features/assistants/agents.test.ts`, `AgentsScreen.stories.tsx` play tests

**Interfaces:**
- Consumes: `useAssistants()` (existing), `BrandLogo`, `SettingsGroup`/`SettingsRow`.
- Produces: `type AgentId = "claude" | "chatgpt" | "lumo" | "grok"`;
  `const AGENTS: readonly { id: AgentId; name: string; brand: BrandName; scene: string; connectorsUrl: string; helpUrl: string; note?: "plan" | "desktop" | "paid" }[]`;
  `agentFor(grant: { name: string; domain?: string | null }): AgentId | null`.

Values (spec "Mis agentes, inside"): scenes `/wambi/handshake-<id>.webp`; connectorsUrl claude
`https://claude.ai/settings/connectors`, chatgpt `https://chatgpt.com/plugins`, lumo
`https://proton.me/lumo/download`, grok `https://grok.com/connectors`; helpUrl claude
`https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp`,
chatgpt `https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt`,
lumo `https://proton.me/support/lumo-connectors`, grok `https://docs.x.ai/grok/connectors`.
`agentFor` matches the grant's name or domain case-insensitively (`claude`/`anthropic`,
`chatgpt`/`openai`, `lumo`/`proton`, `grok`/`x.ai`). Step 2 copy (es):
- claude "En Claude, ve a Ajustes → Conectores → **Añadir conector personalizado** y pega la dirección."
- chatgpt "En **chatgpt.com/plugins**, toca **+** → **Add custom MCP server**, pega la dirección, elige OAuth y toca **Create as a plugin**."
- lumo "En la app de escritorio de Lumo, ve a Settings → Desktop App → Connectors → **Add MCP server** y pega la dirección."
- grok "En grok.com, ve a Conectores → **Nuevo conector** → Personalizado, y pega la dirección."
Notices (es): chatgpt "Se agrega desde la web de ChatGPT, no desde su app móvil; después lo usas
también en el teléfono. Depende de tu plan, y en cada chat nuevo se activa desde el menú +.";
lumo "Solo desde la app de escritorio de Lumo (macOS, Windows o Linux)."; grok "Los conectores
personalizados son de los planes de pago de Grok." Buttons: "Abrir Claude ↗", "Abrir chatgpt.com ↗",
"Descargar Lumo ↗", "Abrir Grok ↗". Help line: "¿Te perdiste? Mira la guía paso a paso en la ayuda
de <Claude|OpenAI|Proton|xAI> ↗". Step 3: "<App> te pedirá entrar: usa tu cuenta de Wambito y
acepta el permiso." Toast: "<App> quedó conectado."

- [ ] **Step 1:** `agents.test.ts`: `agentFor({name:"Claude"}) === "claude"`,
  `agentFor({name:"ChatGPT", domain:"chatgpt.com"}) === "chatgpt"`, `agentFor({name:"Lumo"}) === "lumo"`,
  `agentFor({name:"Grok"}) === "grok"`, `agentFor({name:"Cursor"}) === null`. Stories with play:
  four rows in AGENTS order, connected ones with dates and "Revocar", others "Sin conectar" and
  "Conectar"; an unknown grant "Cursor" listed last with the generic icon and "Revocar"; "Conectar"
  on Claude opens the sheet with the scene, three steps, the help link to its helpUrl; a guest sees
  the email-first line and no "Conectar"; after a window `focus` that brings a new Claude grant, the
  toast shows once. Run → FAIL.
- [ ] **Step 2:** Implement `agents.ts`, the screen (refetch the assistants query on window focus)
  and the sheet (the app's existing sheet/dialog). Remove the old ChatGPT path string.
- [ ] **Step 3:** Tests → PASS. **Commit** `feat(web): mis agentes with a connect sheet per app`.

### Task 10: Mis agentes, phone

**Files:**
- Create: `apps/mobile/lib/settings/agents.dart`, `apps/mobile/lib/settings/connect_agent_sheet.dart`
- Modify: `apps/mobile/lib/settings/assistants_section.dart` (becomes `AgentsScreen`)
- Modify: `apps/mobile/lib/l10n/app_*.arb` (replace `settingsAssistantsChatGpt`; add the rest)
- Test: `apps/mobile/test/settings/agents_test.dart`

**Interfaces:**
- Consumes: `ConnectedAssistant` (`clientId`, `name`, `domain`, `connectedAt`, `lastUsedAt`),
  `settingsAssistantListProvider`, `LkBrandLogo`, `SettingsRow`, `UrlOpener`.
- Produces: `enum Agent { claude, chatgpt, lumo, grok }` with the same fields and values as
  Task 9's `AGENTS`; `Agent? agentFor(ConnectedAssistant a)` with Task 9's rules.

- [ ] **Step 1:** Tests mirroring Task 9's (same names), plus: on
  `AppLifecycleState.resumed` the list provider is invalidated; the toast shows once for a new
  grant. Run → FAIL.
- [ ] **Step 2:** Implement with the copy above (arb), scenes from `assets/wambi/handshake-*.webp`.
- [ ] **Step 3:** Tests → PASS. **Commit** `feat(mobile): mis agentes with a connect sheet per app`.

### Task 11: Cuenta y seguridad, both platforms

**Files:**
- Modify: phone `passkeys_section.dart`, `security/security_section.dart`, `delete_account.dart`;
  web `PasskeysSection.tsx`, `SecuritySection.tsx`, `DeleteAccount.tsx`
- Create: phone `apps/mobile/lib/settings/account_screen.dart`; web `features/settings/AccountScreen.tsx`
- Test: `apps/mobile/test/settings/account_screen_test.dart`, `AccountScreen.stories.tsx` play

Spec section "Cuenta y seguridad, inside" is the contract. Group 1 head icon `fingerprint`,
"Entrar con tu huella", "Sin código, con tu huella o tu cara"; rows: device icon (`laptop` when
the passkey's name or device hint is a computer, else `phone`), name, "Desde el <date>" +
" · sincronizada" when synced, trash "Eliminar <name>"; last row `plus` "Agregar una huella".
Group 2 (encrypted only) head `phone`, "Tus dispositivos", "Pueden abrir tus datos cifrados";
this phone with chip "Este", others with trash "Quitar <name>"; last row "Conectar otro
dispositivo". Row `key` "Clave de recuperación" / "Crea una nueva si la perdiste" (encrypted
only). Danger row `trash` "Eliminar tu cuenta" / "Borra tu cuenta y tus movimientos". The old
leads move into the sheets those rows open. Above the groups, the account email.

- [ ] **Step 1:** Tests: a plain account shows only group 1 and the delete row; an encrypted one
  all four; tapping a passkey's trash asks the existing confirmation; the delete row opens the
  existing delete sheet with its full text and "Descarga tus datos antes". Run → FAIL.
- [ ] **Step 2:** Implement. **Step 3:** → PASS. **Commit** `feat(settings): a lighter cuenta y seguridad`.

### Task 12: Captura, phone

**Files:**
- Create: `apps/mobile/lib/settings/capture_screen.dart`
- Modify: `apps/mobile/lib/capture_auto/auto_capture_section.dart` (rows instead of a card)
- Test: `apps/mobile/test/settings/capture_screen_test.dart`

Spec "Captura, inside" is the contract. Groups: `wand` "Captura automática" / "Desde las
notificaciones de tus apps" (Android only): a switch row per source with `LkBrandLogo` revolut /
googleWallet and line "Activa" or "Apagada"; the missing-permission notice and "Dar acceso" inside
the group; row `info` "¿Cómo funciona?" opens today's explainer. `mic` "Voz" / "Dictar sin
internet" (only with a model installed): switch "Mejorar la precisión" with "+<MB> MB · corrige al
terminar de hablar" or the download progress; danger row "Borrar los modelos de voz". `bell`
"Avisos" / "Lo que Wambito te recuerda": `calendar` "Hoy vence…" (line "A las 9:00, los pagos
que vencen hoy"; iOS "Hacia las 9:00…"), `info` "Si no tienes correo" ("Antes de que se borren tus
datos"). `widget` "Widget" / "Anota desde tu pantalla de inicio" (Android): `plus` "Añadir widget"
while none is on the home screen, `eye-off` "Ocultar el monto". Vibration is not here (Task 13).

- [ ] **Step 1:** Tests: on iOS no auto-capture or widget group; with no voice model no Voz group;
  each switch row toggles its existing provider; permission missing shows "Dar acceso". → FAIL.
- [ ] **Step 2:** Implement. **Step 3:** → PASS. **Commit** `feat(mobile): a lighter captura screen`.

### Task 13: Preferencias, Tus datos and Más, both platforms

**Files:**
- Create: phone `preferences_screen.dart`, `data_screen.dart`, `more_screen.dart`; web
  `PreferencesScreen.tsx`, `DataScreen.tsx`, `MoreScreen.tsx` (in `features/settings/`)
- Modify: phone `time_money_section.dart`, `export_settings.dart`, `feedback.dart`,
  `server_status.dart`; web `PreferencesSection.tsx`, `TimeAndMoneySection.tsx`, `FeedbackSection.tsx`
- Create: a choice sheet for language and theme (phone `choice_sheet.dart`; web `ChoiceSheet.tsx`)
  reusing today's `Choices` inside it
- Test: phone `test/settings/{preferences,data,more}_screen_test.dart`; web stories play tests

Spec "Preferencias, Tus datos and Más, inside" is the contract. Preferencias: label "Apariencia":
`globe` Idioma (value = current language's own name), `moon` Tema (Sistema/Noche/Día); label
"Sonido y tacto": `volume` Sonido "Un sonido corto al anotar", `phone` Vibración (phone) "Un toque
suave al anotar y deshacer"; label "Hora y moneda": `clock` Zona horaria (city), `coin` Moneda
(ISO code; locked state as today). Tus datos: `upload` "Importar movimientos" / "Desde el CSV de
tu banco" (chevron to import; chip "Próximamente" on an encrypted account), `download` "Descargar
tus datos" / "Un CSV con todo lo que anotaste" (today's export choices in a sheet). Más: `chat`
"Comentarios e ideas" / "Cuéntanos qué mejorar" (today's feedback in a sheet); phone also `map` "Lo
que viene", `globe` "Abrir Wambito en la web", then a group with `server` "Servidor" (green dot +
"Conectado" / today's offline state; the address as line; opens today's change-server form) and
`info` "Acerca de" (version; `/settings/about`). The web's Más has only Comentarios.

- [ ] **Step 1:** Tests: Idioma row shows "Español" and its sheet changes language at once; Tema
  sheet applies at once; Moneda locked shows today's locked text in its sheet; encrypted Importar
  shows "Próximamente" and no chevron; export sheet downloads as today; Servidor offline shows
  today's offline text. → FAIL.
- [ ] **Step 2:** Implement. **Step 3:** → PASS. **Commit** `feat(settings): lighter preferencias, tus datos and más`.

### Task 14: Parity, e2e, integration and the vault e2e

**Files:**
- Modify: `apps/mobile/test/parity/settings_parity_test.dart`, `it_pt_parity_test.dart`,
  `parity.json`; `apps/web/app/features/settings/Settings.stories.tsx` (stories per category and
  for the menu; drop the `AppSections*` page stories the menu replaces)
- Modify: `apps/mobile/integration_test/{settings,export,delete_account,notices}_test.dart`
- Modify: `apps/web/e2e/{a11y,demo,vault,overflow-it-pt}.spec.ts`
- Modify: `apps/mobile/test_stack/*` navigation to devices and recovery key

- [ ] **Step 1:** Parity pairs: the menu (`webSectionsOnly`: no Captura; Más line "Comentarios"),
  and each shared category screen (agents, account, preferences, data, more) in es night, en day,
  it, pt; regenerate goldens and the stories' snapshots.
- [ ] **Step 2:** Update every integration and e2e test that walked the long page to go through
  the menu; `overflow-it-pt` covers the menu and each category page.
- [ ] **Step 3:** Run `pnpm test`, web e2e against the pinned-clock stack, `flutter test`
  (with goldens), `apps/mobile/scripts/run-vault-e2e.sh` → all PASS.
- [ ] **Step 4: Commit** `test(settings): parity and e2e through the settings menu`.

### Task 15: Docs and the screens map

**Files:**
- Modify: `apps/mobile/AGENTS.md`, `apps/web/AGENTS.md` (Settings is a menu plus category routes;
  the shared rows; brands.json), `docs/AGENTS.md` (brands.json next to icons.json)
- Figma screens map (founder's file): the menu, six category screens, four connect sheets, arrows

- [ ] **Step 1:** Update the three AGENTS.md files.
- [ ] **Step 2:** With the Figma MCP (`use_figma`), add the screens to the web and mobile pages;
  if Figma is not connected, say so in the PR description.
- [ ] **Step 3:** Before merging, by hand: connect Grok once (if it fails, flip Grok to
  "Próximamente" in `AGENTS` and the phone enum); check ChatGPT's menu names at chatgpt.com/plugins
  and Lumo's in its desktop app; open the four help links.
- [ ] **Step 4: Commit** `docs: settings by category in the agent maps`.
