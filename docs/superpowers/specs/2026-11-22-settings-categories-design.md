# Settings by category: a short menu with icons

Date: 2026-11-22. Status: design, waiting for approval.

Calls made by the writer, not discussed with the founder: the five other category names and what
goes in each; vibration moving to Preferencias and the notices and widget to Captura; the summaries'
content; "Cerrar sesión" under the menu; the route names.

## Why

Settings is hard to read: it is one long page of up to 15 cards (phone) or 6 to 8 (web), each with a
large title, a lead line, a hint under every switch and a full-width button per action. Finding one
thing means scrolling past everything else. The founder wants it shorter and easier to read, with
icons, and the AI agents ("Mis agentes") easy to find: it is one of the most important parts of
Wambito and today it sits in the middle of the page.

Built on `origin/main` as of 2026-11-22 (after `797ae6de`): the phone connects and manages
assistants on encrypted accounts too, and Security has its new device and key screens. Branch from
there, not from an older checkout.

## Goals

- Settings opens on a menu that fits one phone screen without scrolling: one row per category, each
  with an icon, a name and a short line showing its current state.
- "Mis agentes" is its own category, first in the menu, showing the four apps it works with.
- Each category opens its own screen with only its settings. Inside, the existing sections keep
  their content and their explanations (there is room for them now).
- Phone (Flutter) and web change together and stay alike, as today.

## Non-goals

- No new settings, and none removed. No change to the API or to the MCP. The one addition is in
  "Mis agentes": the steps to connect Lumo+ and Grok next to the existing ones for Claude and
  ChatGPT (see below).
- Every category screen is redrawn inside in the light pattern (below); no setting is added or
  removed, and every long explanation moves into the sheet or flow its row opens.
- Not a change to the design system's look (colours, type, cards, switches).

## Anti-goals (a failure even if it works)

- The menu itself scrolls on an ordinary phone (360 x 740 dp, font at 100 %).
- A setting becomes harder to reach than today for someone who knows where it was (more than one
  extra tap).
- The urgent account states ("Protege tus datos", "Guarda tu progreso") get buried inside a
  category.
- The phone and the web drift apart in names, order or what is in each category.

## Approaches considered

1. **Menu of categories, each opens its own screen** (Android/iOS Settings style). Chosen. Every
   screen is about one thing, the menu shows each category's state at a glance, and the existing
   section widgets/components move almost as they are. Cost: new routes on both platforms, the
   parity tests and the e2e/integration tests that walk Settings need updating, and the Figma screens
   map needs the new screens. Chosen by the founder, with "Mis agentes" as its own category,
   first, and the phone and the web changing together.
2. **One page, compact rows.** Small group headings, one-line rows with icon and value, language and
   theme as rows that open a sheet, hints hidden. About a third of today's height, no new routes. Not
   chosen: still a scroll, and passkeys and security stay big blocks in the middle.
3. **Collapsible sections (accordion).** Cheap, but opening security or passkeys makes the page long
   again, and the current state of each thing is hidden while closed. Not chosen.

## The menu

```
Ajustes
Entraste como ana@…
[Protege tus datos / Guarda tu progreso block, when it applies]
──────────────────────────────
[4 logos] Mis agentes         ›
    ChatGPT · Claude · Lumo+ · Grok
👤  Cuenta y seguridad        ›
    passkeys, dispositivos, clave
🎨  Preferencias              ›
    Español · Noche · COP
🎙  Captura                   ›
    automática, voz, avisos
📁  Tus datos                 ›
    importar, exportar
ℹ️  Más                        ›
    servidor, web, comentarios, acerca de
──────────────────────────────
     Cerrar sesión
```

(The emoji only stand for icons. The approved look, from the mockups of 2026-11-22: each row is a
`lk-rowcard` with a 40 px icon tile (`radius-sm`, `surface-sunken`, the icon in `brand`). "Mis
agentes" uses the same tile as the others (founder's decision: it must not look like a button); its
icon is the four apps' logos in `brand`, two by two.)

- Header as today: the title and "Entraste como…".
- The urgent block stays above the menu, never inside a category: `ProtectBlock` for a `preview`
  account without email, "Guarda tu progreso" for a `plain` guest.
- One row per category: icon (22 px, like the other interface icons), name, a muted one-line
  summary, a chevron. The whole row is one button, at least 44 px tall, with the press and focus
  styles of the other rows.
- The summary shows state where there is one:
  - Mis agentes: the four apps' names, "ChatGPT · Claude · Lumo+ · Grok" (founder's decision). It
    is fixed text, so the menu needs no request; what is connected shows inside.
  - Preferencias: language · theme · currency.
  - The others: what is inside, as a short list of words.
- "Cerrar sesión" stays under the menu, visible (phone; the web keeps signing out where it is today).
- Under it, centred and muted, the app's version: "Wambito 1.0.4" (the installed build's version;
  founder's request). It stays in "Acerca de" too.

## What goes in each category

| Category | Phone | Web |
|---|---|---|
| Mis agentes | `AssistantsSection`, reworked (below) | `AssistantsSection`, reworked (below) |
| Cuenta y seguridad | `PasskeysSection`, `SecuritySection` (encrypted accounts), Borrar cuenta (`DeleteAccountCard`) at the bottom | `PasskeysSection`, `SecuritySection`, `DeleteAccount` at the bottom (the web's `ProtectSection` and its `AddEmail` takeover go above the menu, like the phone's `ProtectBlock`) |
| Preferencias | language, theme, sound, vibration; `TimeAndMoneySection` | `PreferencesSection`, `TimeAndMoneySection` |
| Captura | `AutoCaptureSection` (Android), voice models (when installed), the due and guest notices, the widget rows (Android) | not shown (the web has none of these) |
| Tus datos | import, `ExportBlock` | import, export |
| Más | `FeedbackSection`, server, web and roadmap links, About (and the debug PRF probe) | `FeedbackSection` |

Vibration moves from the old "Teléfono" card to Preferencias, next to sound. The notices and the
widget move to Captura: they are about what the app records and reminds.

A category with nothing to show on this platform or for this account is not in the menu.

The offline first run (provisional account) keeps showing only the preferences and why the account
waits: it can open straight on Preferencias' content, as today, with no menu.

## Cuenta y seguridad, inside (approved look, mockups 2026-11-22)

The sections are not moved as they are here: the founder found them too heavy. The screen is
grouped lists with icons and one line of text each:

- Under the title, the account's email.
- A group "Entrar con tu huella" (fingerprint icon, "Sin código, con tu huella o tu cara"): one row
  per passkey (a device icon, its name, "Desde el <date>", "sincronizada" when synced) with a red
  trash icon button (labelled "Eliminar <name>", confirms as today); last row "+ Agregar una huella".
- A group "Tus dispositivos" (encrypted accounts; "Pueden abrir tus datos cifrados"): one row per
  device (phone or laptop icon), this phone with an "Este" chip and no trash; the others with the
  trash button ("Quitar", confirms as today); last row "+ Conectar otro dispositivo".
- A row "Clave de recuperación" (padlock-key icon, "Crea una nueva si la perdiste", chevron): opens
  today's flow; its explanation moves into that flow.
- A row "Eliminar tu cuenta" in the danger colour (trash icon, "Borra tu cuenta y tus
  movimientos", chevron): opens today's delete sheet, which keeps the full explanation and the
  export-first link.
- The long leads (what a passkey is, what a new recovery key does, what deleting removes) move into
  the sheet or flow each action opens; none is lost.
- Icons, Plump Solid (free): Fingerprint 2, Phone Vibrate, Laptop, Padlock Key, Recycle Bin 2; "+"
  is the design system's `plus`.

## Captura, inside (mockups 2026-11-22)

The same light pattern as Cuenta y seguridad: groups with an icon head and one-line rows.

- "Captura automática" (Android; magic-wand icon, "Desde las notificaciones de tus apps"): one switch
  row per source (Revolut, Google Wallet) as today, each with its logo in one colour (`currentColor`,
  muted like the other row icons): Revolut from Simple Icons (CC0), Google Wallet from Font Awesome
  Free (CC BY 4.0, credit it), both through Streamline; the missing-permission notice and its "Dar
  acceso" button stay in this group; a row "¿Cómo funciona?" opens today's explainer.
- "Voz" (the design system's `mic`; shown when a model is installed): "Mejorar la precisión" switch
  with its size and download progress in the line under it; "Borrar los modelos de voz" as a red row
  that confirms as today.
- "Avisos": "Hoy vence…" and the guest notice, as switches with one short line each (the full
  wording moves to the switch's semantics label and stays in the l10n files).
- "Widget" (Android): "Añadir widget" (while none is on the home screen) and "Ocultar el monto".
- Icons, Plump Solid (free): Magic Wand 1, Calendar Mark, Widget, Invisible 1; plus the bell and
  info icons already chosen.

## Preferencias, Tus datos and Más, inside (mockups 2026-11-22)

- The shared pattern: groups on `surface-row` (2px `stroke`, `radius-lg`, `edge-sm`), an optional
  small uppercase label, rows with a 20 px muted icon, a bold name, one muted line, and on the right
  a value + chevron, a switch, a chip or a trash button.
- Preferencias: "Apariencia" — Idioma (value, e.g. "Español") and Tema ("Noche"), each opening a
  sheet with today's choices instead of the big option buttons; "Sonido y tacto" — Sonido and
  Vibración (phone) switches; "Hora y moneda" — Zona horaria and Moneda as value rows opening
  today's pickers from `TimeAndMoneySection`.
- Tus datos: "Importar movimientos" (a chevron to `/import`; on an encrypted account a "Próximamente"
  chip, as today) and "Descargar tus datos" (opens today's export choices).
- Más: "Comentarios e ideas" (today's feedback, in a sheet), "Lo que viene" (roadmap) and "Abrir
  Wambito en la web" (phone); a second group with "Servidor" (status dot and "Conectado", the
  address under it; opens today's change-server form) and "Acerca de" (the version; opens
  `/settings/about`). The web shows only Comentarios.
- "Cerrar sesión" stays under the menu, not in Más.
- Icons, Plump Solid (free): Earth 1, Moon Stars, Volume Level High, Circle Clock, Dollar Coin,
  Upload Box 1, Download Box 2, Database Server 3, Map Fold.

## Phone

- `/settings` is the menu. Each category is a child route: `/settings/agents`,
  `/settings/account`, `/settings/preferences`, `/settings/capture`, `/settings/data`,
  `/settings/more`. Existing children (`about`, `signin`) stay where they are.
- Each category screen uses the same page frame as Settings today (`ManagePage` with the back header)
  and its title is the category's name; back returns to the menu.
- Links that open Settings for a reason go to the right category: the web sign-in notice
  (`security/signin_notice.dart`) to `/settings/account`; `home_actions.dart` stays on `/settings`.

## Web

- Like the phone at every width: `/app/settings` is the menu, and a category opens on its own page
  with a back link, inside the same `ManageFrame` (720 px cap) as today. No two-pane layout: the
  app shell already has a sidebar on wide screens, and a third column would not fit (founder's
  decision, 2026-11-22).
- Each category has its own URL (`/app/settings/agents`, ...) so a link, a reload or the back
  button lands in the same place. Same for the demo's settings route.
- Links into Settings (`admin/VerifyScreen.tsx`) keep pointing at `/app/settings` unless a category
  fits better.

## Mis agentes, inside

- A lead line: use Wambito from your AI assistant, to note movements and ask how you are doing.
- A card listing the four apps, each a row with its logo (monochrome, `ink` on a `surface-sunken`
  tile) and its name:
  - connected: when it was connected and last used, and "Revocar" (as today);
  - not connected: "Sin conectar" and a "Conectar" button that opens a bottom sheet (approved in
    the mockups for Claude): at the top Wambi's handshake scene with that app (below; the only place
    the logos are in colour), then "Conectar <app>", three numbered steps — 1. copy the
    connector address (field + "Copiar"), 2. where to paste it in that app, with an "Abrir <app> ↗"
    button to its connectors page, 3. sign in with the Wambito account and accept — then the
    existing "Luego pídele…" examples and a primary "Listo". On the web, the same content in the
    app's sheet/dialog.
  - Back on the page (the app resumed, or the web tab focused), the list is fetched again; a new
    grant shows as connected with a toast "<app> quedó conectado."
- A grant whose app is none of the four (another MCP client) still shows, with a generic icon, so it
  can be revoked.
- The connector address card stays, with "Copiar".
- A guest sees why they need an email first, as today.
- Steps per app, in the four languages:
  - Claude and ChatGPT: the existing ones.
  - ChatGPT: only on the web, chatgpt.com/plugins (ChatGPT's mobile apps cannot add a custom MCP
    server; once added on the web it works on the phone too — OpenAI help "Connecting custom MCP
    servers in ChatGPT"). The notice says so and the step-2 button opens chatgpt.com/plugins in the
    browser. Path: Plugins → + → Add custom MCP server → the address, OAuth → Create as a plugin (the
    flow that replaced "Developer mode"; the old "Ajustes → Conectores" path no longer exists, per
    the founder, 2026-11-22). A notice: custom connectors depend on the plan, and the plugin is
    turned on per chat from the + menu. The app's current `settingsAssistantsChatGpt` string (all
    four languages, phone and web) has the old path and is replaced. Check the menu names against
    ChatGPT itself before merging.
  - Lumo+: only from the Lumo desktop app (macOS, Windows, Linux): Settings → Desktop App →
    Connectors → Add MCP server (as the founder connected it to Wambito, 2026-11-22; Proton's
    support page still says Customize → Connectors). A notice says it is the desktop app only, and
    the step-2 button is "Descargar Lumo ↗".
  - Grok: grok.com → Conectores → Nuevo conector → Personalizado (xAI's docs); a notice that custom
    connectors are on Grok's paid plans. Not tried yet: connect it once before merging, and if it
    fails, show Grok as "Próximamente" instead of "Conectar".
  - The sheet is the same for all four (approved in the mockups): the scene, "Conectar <app>", the
    app's notice when it has one, the three steps, a help link ("¿Te perdiste? Mira la guía paso a
    paso en la ayuda de <company> ↗", opens in the browser), the examples, "Listo".
  - Help links (check each still resolves before merging; prefer the page in the person's language
    when the company has one):
    - Claude: https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp
    - ChatGPT: https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt
    - Lumo+: https://proton.me/support/lumo-connectors
    - Grok: https://docs.x.ai/grok/connectors
- How a grant maps to one of the four apps (by the OAuth client's name or id) is the builder's to
  find in the API's assistants list.

## Wambi's handshake scenes

- The connect sheet opens with a scene: Wambi shaking hands with the app, drawn as a character made
  from the app's logo (its tile and mark in the brand's colours, with the same purple arms and legs
  and pink sneakers as Wambi). Founder's decision, 2026-11-22, over a brand-free speech-bubble
  alternative.
- One scene per app: `wambi-handshake-claude`, `-chatgpt`, `-lumo`, `-grok`, all four made and
  approved in the mockups (2026-11-22). Codex, `codex exec` image generation from
  `wambi-pointing.webp` and each logo; Claude's first, with a second pass so Wambi's arm comes from
  the coin's rim and not his face, then the other three from Claude's scene as the reference for
  pose and style (variant A of each). No ground shadow. ChatGPT and Grok: their white marks on a
  black tile; Lumo+: its app icon, a white tile with the purple cat printed flat on it (founder's
  correction: the app's icon, not the cat as a character).
- An exception to the Wambi scenes' rule of no logos (`docs/AGENTS.md`): add it there, for these
  four files only. Risk the founder accepted: each logo is a trademark and is drawn altered (with
  limbs); if a company objects, swap that scene for the logo tile beside the waving Wambi.
- Checked by eye on night and day. 1024 px masters in `docs/brand/`, byte-identical 512 px copies
  with transparency in `apps/web/public/wambi` and `apps/mobile/assets/wambi`, as the other scenes.
- The sheet's title row then needs no separate logo; "Conectar <app>" sits under the scene.

## Icons and logos

- Six category icons, from Streamline's **Plump Solid (free)** set, the same family as the existing
  `home` and `chart` (CC BY 4.0, credited in `icons.json`'s `$comment` like those): Shield 1
  (Cuenta y seguridad), Horizontal Slider Square (Preferencias), Ringing Bell Notification
  (Captura), File Folder (Tus datos), Information Circle (Más). They join
  `docs/design/system/project/icons/icons.json` and are drawn by `apps/web/app/ui/Icon.tsx` and
  `apps/mobile/lib/ui/lk_icon_shapes.dart`, as the existing icons are.
- The four apps' logos, monochrome (`currentColor`), never in brand colours: ChatGPT (OpenAI), Claude
  and Grok from Streamline's **Logos Solid (free)** set in the mockups; Lumo+ from Proton's own icon
  (`lumo-2-icon.svg` on proton.me/lumo), made one colour by turning its white details into cut-outs. Before shipping, prefer each company's official mark where its brand guidelines allow a
  monochrome use, and keep a note of each logo's source next to it. They show which apps Wambito
  works with, nothing more (no "partner" or "official" wording).

## Names and copy

- New strings in all four languages (es, en, it, pt) on both platforms: the six category names, the
  summaries, "Sin conectar", "Conectar", and the Lumo+ and Grok steps.
- The category is "Mis agentes" (founder's decision); the app names are never translated.
- The old card titles that become category screens' titles are reused where they fit.

## Tests and the rest of the change

- Write the failing tests first: the menu's rows and order per platform and account kind, the
  summaries, each route showing its sections, back navigation, the web at phone and desktop widths.
- Parity: the phone's `webSectionsOnly` view of the menu hides what the web does not have (Captura,
  and Más' server, web links and About), so the menu pair is compared like today's page; each
  category screen gets its own pair, assistants included now. (Builder's call.)
- Update what walks Settings today: the phone's `test/parity/settings_parity_test.dart` and
  `parity.json` against the web's `Settings.stories.tsx` (new stories per category and for the
  menu), `integration_test/settings_test.dart`, `export_test.dart`, `delete_account_test.dart`,
  `notices_test.dart`, and the web's `e2e/settings.spec.ts`, `a11y.spec.ts`, `demo.spec.ts`,
  `vault.spec.ts`, `overflow-it-pt.spec.ts`.
- The phone's `test_stack` vault e2e taps through Settings (devices, recovery key): update its
  navigation.
- Update the Figma screens map (web and mobile pages) with the menu and the six category screens and
  their arrows, or say in the PR that Figma was not connected.
- Update `apps/mobile/AGENTS.md` and `apps/web/AGENTS.md` where they describe Settings.
- No API or MCP change, so no CHANGELOG line.

## Left to the builder

- The exact icons, within the design system's style.
- Splitting the phone's `settings_screen.dart` (823 lines) into a menu and one file per category.
- The exact summary wording in each language, within the length that fits one line at 360 dp.
