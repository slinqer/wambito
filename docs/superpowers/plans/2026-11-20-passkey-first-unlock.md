# Passkey-first Unlock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A PRF passkey opens the data with the sign-in's one touch on web and phone, the unlock screen leads with what will work on this device, and the recovery key sits under "More options" with a field that groups and pastes.

**Architecture:** No server change. Each client gains two inputs for the unlock screen: a non-secret per-device hint ("the last passkey touched here gave no PRF") and whether the account has a passkey wrap (`GET /v2/keys`). A pure function picks one of three layouts from them. The phone copies the web's one-shot sign-in PRF stash and wires the gate's existing `takeSignInPrf`.

**Tech Stack:** TypeScript, React Router, use-intl, Vitest, Storybook, Playwright (`apps/web`); Flutter, Riverpod (`apps/mobile`).

**Spec:** `docs/superpowers/specs/2026-11-20-passkey-first-unlock-design.md`

## Global Constraints

- No change to the keys, the wraps, the API or the MCP. No `CHANGELOG.md` line.
- The PRF is never written to disk, never logged, and is zeroed after use, on sign-out, when it is another account's, and once the vault is open.
- The hint holds a boolean per user id, never a credential id. Sign-out keeps it.
- No automatic passkey prompt when the unlock screen opens.
- A person whose passkey has no PRF never sees a main button that cannot work without the recovery-key field in sight.
- Recovery key shape: `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXX` (27 characters with dashes). The parser (`packages/crypto/src/recovery.ts`) stays the judge; `O`, `I` and `L` are kept as typed.
- Copy in es, en, it and pt (PT-PT). Spanish says "clave" for the recovery key and "huella" for the passkey on the unlock screen; the phone's sign-in button "Usar passkey" becomes "Entrar con huella". Other languages keep their sign-in wording for the passkey.
- Exact Spanish copy: main button "Abrir con mi huella"; disclosure "Más opciones"; no-PRF line "Tu huella te deja entrar, pero tu gestor de contraseñas no le permite abrir tus datos."; other passkey "Usar otra huella"; paste "Pegar"; add notice "Esta huella sirve para entrar, pero tu gestor de contraseñas no le permite abrir tus datos. Guarda tu clave de recuperación: la vas a necesitar en un dispositivo nuevo."
- Failing tests first. Everything in the repo in English. Stage by path. Commits `feat(area): …`, no `Co-Authored-By`.
- Generated files are regenerated (Flutter l10n by `flutter pub get`), never hand-edited.

## Review Focus

1. A Proton-style account (a passkey, no passkey wrap) after a reload: the recovery-key field is still the main action. Test: Task 2 (`unlockLayout`), Task 3 e2e.
2. The wraps cannot be read (offline, 5xx): the screen assumes a passkey wrap exists and still shows the recovery key one tap away; nothing throws. Test: Task 2.
3. A paste with line breaks, lower case and no dashes, or with a trailing space, yields a full key and enables submit. Test: Task 1.
4. A passkey sign-in for account A, then the session becomes account B before the gate runs: A's PRF is zeroed and B's hint is untouched. Test: Task 2 (web), Task 5 (phone).
5. Deleting a character just after a dash removes the character before the dash and keeps the caret there, not at the end. Test: Task 1.

---

### Task 1: Web recovery-key field

**Files:**
- Create: `apps/web/app/features/vault/recovery-key-input.ts`, `apps/web/app/features/vault/recovery-key-input.test.ts`, `apps/web/app/features/vault/RecoveryKeyField.tsx`
- Modify: `apps/web/app/features/vault/Unlock.tsx` and `apps/web/app/features/sign-in/RecoveryKeySignIn.tsx` (both use the field), `apps/web/app/i18n/messages/app.{es,en,it,pt}.json` (`vault.unlock.paste`)
- Test: the two story files' play functions (`Unlock.stories.tsx`, `SignIn.stories.tsx`)

**Interfaces:**
- Produces:
  - `groupRecoveryKey(text: string): string`: upper case, only the key's alphabet plus `O`, `I`, `L`, at most 27 characters, a dash after every fourth.
  - `groupRecoveryKeyEdit(previous: string, next: string, caret: number): { text: string; caret: number }`: the grouped text and where the caret goes.
  - `isFullRecoveryKey(text: string): boolean`: 27 grouped characters.
  - `<RecoveryKeyField id value onChange invalid describedBy disabled />`: one input, with a "Paste" button when `navigator.clipboard?.readText` exists.

- [ ] **Step 1: Failing unit tests** in `recovery-key-input.test.ts`:
  - `groups while typing`: `groupRecoveryKey("abcd2")` is `"ABCD-2"`.
  - `regroups a paste in any shape`: `"abcd efgh\n2345-6789 abcd efgh 234 "` gives `"ABCD-EFGH-2345-6789-ABCD-EFGH-234"`.
  - `keeps O, I and L, drops what the alphabet lacks`: `groupRecoveryKey("o0il!?")` is `"O0IL"`.
  - `never grows past a full key`.
  - `deleting just after a dash removes the character before it and keeps the caret`: previous `"ABCD-E"`, next `"ABCDE"`, caret 4 gives `{ text: "ABC-E"… }` with the caret at 3. Fix the exact expected value from the implementation's rule and assert it.
  - `typing in the middle keeps the caret after the typed character`.
  - `isFullRecoveryKey` is true only at 27.
- [ ] **Step 2:** Run `pnpm --filter @wambito/web test recovery-key-input`; expect failures.
- [ ] **Step 3:** Implement the three functions, then `RecoveryKeyField` (the current input's classes and attributes from `Unlock.tsx`; sets the caret with `setSelectionRange` after each change).
- [ ] **Step 4:** Use the field in `Unlock.tsx` and `RecoveryKeySignIn.tsx`; submit enables on `isFullRecoveryKey`. Add story plays: typing `abcd2345…` shows the dashes; the submit enables only on a full key.
- [ ] **Step 5:** Run the unit tests, `pnpm --filter @wambito/web test-storybook` for the two story files, `pnpm typecheck`, `pnpm lint`.
- [ ] **Step 6:** Commit `feat(web): a recovery-key field that groups and pastes`.

### Task 2: Web unlock inputs: the device hint, the passkey wrap, the layout

**Files:**
- Create: `apps/web/app/local/unlock-hint.ts`, `apps/web/app/local/unlock-hint.test.ts`, `apps/web/app/features/vault/unlock-layout.ts`, `apps/web/app/features/vault/unlock-layout.test.ts`
- Modify: `apps/web/app/features/vault/vault-gate.ts` (+ `vault-gate.test.ts`), `apps/web/app/features/vault/VaultGate.tsx`, `apps/web/app/features/sign-in/auth.ts` (+ `auth.test.ts`), `apps/web/app/local/keys.ts` (a reader for "has a passkey wrap")

**Interfaces:**
- Produces:
  - `unlock-hint.ts`: `passkeyGaveNoPrf(userId: string): boolean`, `notePasskeyWithoutPrf(userId: string): void`, `notePasskeyOpened(userId: string): void`, `forgetUnlockHint(userId: string): void`. Storage key `wambito.unlock.no-prf.<userId>`, value `"1"`; every access in try/catch, false when storage is unavailable.
  - `keys.ts`: `hasPasskeyWrap(options: KeysOptions): Promise<boolean>` from `listWraps` (a wrap whose kind is the passkey kind in `WrapDto`).
  - `unlock-layout.ts`: `type UnlockLayout = "key_first" | "passkey_first" | "pair_first"` and `unlockLayout(input: { noPrfHere: boolean; passkeyWrap: boolean; passkeysSupported: boolean; canPair: boolean }): { main: "key" | "passkey" | "pair"; below: Array<"pair">; more: Array<"key" | "passkey"> }`.
  - Gate: state `{ status: "unlock"; notice?; means: { noPrfHere: boolean; passkeyWrap: boolean } }`; new deps `passkeyGaveNoPrf?(): boolean`, `notePasskeyWithoutPrf?(): void`, `notePasskeyOpened?(): void`, `hasPasskeyWrap?(): Promise<boolean>`.

- [ ] **Step 1: Failing tests.**
  - `unlock-layout.test.ts`, one per row of the spec's table plus:
    - `no PRF here: the key is main, another passkey is under more only with a passkey wrap`;
    - `a passkey wrap and passkey support: the passkey is main, the key under more`;
    - `no passkey wrap: pairing is main, the key under more`;
    - `nothing above more (no pairing, no passkey): the key is main and more is empty`;
    - `no passkey support with a wrap: pairing main, key under more`.
  - `unlock-hint.test.ts`: set, read, clear, per user; a throwing `localStorage` reads false and never throws.
  - `vault-gate.test.ts`:
    - `the unlock state carries the hint and the wrap`;
    - `an unreadable wraps list counts as a passkey wrap`;
    - `a passkey touch without PRF notes the hint` (`evaluatePrf` throwing `no_prf`);
    - `a passkey that opens the data clears the hint`;
    - `the sign-in's PRF of another account is zeroed and no hint is written for this one`.
  - `auth.test.ts`: `a passkey sign-in without PRF notes the hint for the user who signed in`; `with PRF it does not`.
- [ ] **Step 2:** Run those test files; expect failures.
- [ ] **Step 3:** Implement. In `auth.ts` `keepPrfOf` notes the hint when the sign-in succeeded and `readPrf` was null. The gate reads `means` before it sets `unlock` (both places that set it, and after `unverified`/`removed`); `hasPasskeyWrap` failures give `true`.
- [ ] **Step 4:** Wire the deps in `VaultGate.tsx` (`hasPasskeyWrap` through `signInAgainOn401`). Account deletion's local cleanup calls `forgetUnlockHint`.
- [ ] **Step 5:** Run the web unit tests for `app/local` and `features/vault`, `features/sign-in`; typecheck; lint.
- [ ] **Step 6:** Commit `feat(web): the unlock screen knows what can open the data here`.

### Task 3: Web unlock screen, sign-in page, add-passkey notice

**Files:**
- Modify: `apps/web/app/features/vault/Unlock.tsx`, `Unlock.stories.tsx`, `VaultGate.tsx`, `apps/web/app/features/assistants/Consent.tsx` (+ stories), `apps/web/app/features/sign-in/SignIn.tsx` (+ stories), `apps/web/app/features/settings/PasskeysSection.tsx` (+ `Security.stories.tsx`), `apps/web/app/features/sign-in/PasskeyOffer.tsx` (+ stories), `apps/web/app/i18n/messages/app.{es,en,it,pt}.json`, `apps/web/e2e/vault.spec.ts`, `apps/web/AGENTS.md`

**Interfaces:**
- Consumes: Task 1's field; Task 2's `unlockLayout`, the gate's `means`.
- Produces: `Unlock` props gain `means?: { noPrfHere: boolean; passkeyWrap: boolean }` (default `{ noPrfHere: false, passkeyWrap: true }`).

- [ ] **Step 1: Failing story plays** (`Unlock.stories.tsx`), one story per layout:
  - `KeyFirst`: the field and the no-PRF line are visible; "More options" holds "Usar otra huella".
  - `PasskeyFirst`: "Abrir con mi huella" is the primary button; the field is not in the document until "Más opciones" is opened.
  - `PairFirst`: pairing is primary; the field is under "Más opciones".
  - `PasskeyFails`: `onPasskey` resolving `no_prf` opens "Más opciones" by itself and shows the error.
  - `ConsentNoPairing`: no pairing, no passkey: the field is main and there is no disclosure.
  - `SignIn.stories.tsx`: the recovery-key form is not visible until "Más opciones" is opened; opening shows the field directly.
  - `Security.stories.tsx` and `PasskeyOffer.stories.tsx`: adding a passkey that ends without a wrap shows the add notice as persistent text (`role="status"`), not a toast.
- [ ] **Step 2:** Run `test-storybook` for those files; expect failures.
- [ ] **Step 3:** Implement the layouts from `unlockLayout` with a native `<details>`-like disclosure the project's UI already has (or a button with `aria-expanded`); `VaultGate.tsx` passes `state.means`; `Consent.tsx` passes its own (`noPrfHere` from the hint, `passkeyWrap` from what it already knows). Move the copy: every `vault.unlock` string saying "llave de acceso" says "huella" in es; add `more`, `no_prf_line`, `other_passkey`, and the add notice in four languages.
- [ ] **Step 4: e2e** in `vault.spec.ts`:
  - update `a passkey unlocks with PRF` to the new labels;
  - new `a passkey without PRF signs in and the recovery key opens the data`: a virtual authenticator with `hasPrf: false`; add the passkey in Settings and see the add notice and "No abre tus datos"; sign out; sign in with it; the unlock screen shows the field and the no-PRF line; reload, and it still does; paste the key without dashes and in lower case; the movements show.
- [ ] **Step 5:** Run the web unit tests, `test-storybook`, the `vault.spec.ts` e2e on the pinned stack (`apps/web/AGENTS.md`), typecheck, lint.
- [ ] **Step 6:** Update `apps/web/AGENTS.md` (unlock layouts, the hint, the field). Commit `feat(web): passkey-first unlock, the recovery key under more options`.

### Task 4: Phone: the sign-in's PRF opens the vault

**Files:**
- Create: `apps/mobile/lib/vault/sign_in_prf.dart`, `apps/mobile/lib/vault/unlock_hint.dart`
- Modify: `apps/mobile/lib/api/session.dart`, `apps/mobile/lib/vault/vault_providers.dart`, `apps/mobile/lib/vault/vault_gate.dart`, `apps/mobile/lib/local/prf.dart` (share the "add the PRF extension to options" step)
- Test: `apps/mobile/test/api/session_vault_test.dart`, `apps/mobile/test/vault/vault_gate_test.dart`, `apps/mobile/test/vault/vault_providers_test.dart`, new `apps/mobile/test/vault/unlock_hint_test.dart`

**Interfaces:**
- Produces:
  - `sign_in_prf.dart`: `class SignInPrf { void keep(String userId, PasskeyPrf prf); PasskeyPrf? take(String userId); void clear(); }` and `signInPrfProvider`, shaped like `signInRecoveryKeyProvider` (memory only; `take` for another user zeroes and returns null).
  - `prf.dart`: `String withPrfExtension(String optionsJson)` and `PasskeyPrf? prfOfAssertion(String assertionJson)` (null without a 32-byte PRF).
  - `unlock_hint.dart`: `class UnlockHint { Future<bool> gaveNoPrf(String userId); Future<void> noteWithoutPrf(String userId); Future<void> noteOpened(String userId); Future<void> forget(String userId); }` on a new pref key `wambito.unlock.no_prf.<userId>`, and `unlockHintProvider`.
  - Gate: `Unlock` gains `final bool noPrfHere; final bool passkeyWrap;` deps `passkeyGaveNoPrf`, `notePasskeyWithoutPrf`, `notePasskeyOpened`, `hasPasskeyWrap` (as the web's in Task 2).

- [ ] **Step 1: Failing tests.**
  - `session_vault_test.dart`:
    - `a passkey sign-in asks for the PRF` (the options given to the fake `Passkeys.get` carry `extensions.prf.eval.first`), for `signInWithPasskey` and `signInWithAvailablePasskey`;
    - `a passkey sign-in with a PRF keeps it for that user`;
    - `one without a PRF keeps nothing and notes the hint`;
    - `sign-out clears the kept PRF`;
    - `a failed sign-in keeps nothing`.
  - `vault_providers_test.dart`: `the gate opens with the sign-in's PRF and shows no unlock screen`; `another account's PRF is zeroed`.
  - `vault_gate_test.dart`: the web's five gate tests of Task 2, in Dart.
  - `unlock_hint_test.dart`: set, read, clear, per user.
- [ ] **Step 2:** Run `flutter test test/api/session_vault_test.dart test/vault`; expect failures.
- [ ] **Step 3:** Implement. `_finishPasskeySignIn` reads the PRF from the assertion and, once `standing.userId` is known and the sign-in succeeded, keeps it or notes the hint; without a user id the PRF is zeroed. Every place that clears `signInRecoveryKeyProvider` also clears `signInPrfProvider`. `vault_providers.dart` wires `takeSignInPrf`, the hint deps and `hasPasskeyWrap` (from `keys.listWraps`, `true` on failure).
- [ ] **Step 4:** Run the tests above, `flutter analyze`.
- [ ] **Step 5:** Commit `feat(mobile): the passkey that signs in opens the data`.

### Task 5: Phone unlock screen, recovery-key field, copy

**Files:**
- Create: `apps/mobile/lib/vault/recovery_key_input.dart`, `apps/mobile/lib/vault/unlock_layout.dart`
- Modify: `apps/mobile/lib/vault/unlock_view.dart`, `apps/mobile/lib/vault/vault_screen.dart`, the `/entry/recovery` screen's field, `apps/mobile/lib/protect/protect_actions.dart` and the settings passkeys section (the add notice), `apps/mobile/lib/l10n/app_{es,en,it,pt}.arb`, `apps/mobile/AGENTS.md`
- Test: new `apps/mobile/test/vault/recovery_key_input_test.dart`, `unlock_layout_test.dart`; `apps/mobile/test/vault/vault_screen_test.dart`; the existing tests of the recovery sign-in screen and of the passkeys section

**Interfaces:**
- Consumes: Task 4's `Unlock.noPrfHere` / `passkeyWrap`.
- Produces: `groupRecoveryKey(String)`, `isFullRecoveryKey(String)`, a `TextInputFormatter` `RecoveryKeyFormatter`; `unlockLayout(...)` with the web's inputs and result (Task 2).

- [ ] **Step 1: Failing tests.**
  - `recovery_key_input_test.dart` and `unlock_layout_test.dart`: the same cases as the web's Task 1 and Task 2.
  - `vault_screen_test.dart`: the three layouts (`key first shows the field and the line`, `passkey first hides the field until More options`, `pair first`), `a failed passkey touch opens More options`, `Paste fills and groups the field`.
  - Passkeys section / protect: `adding a passkey without PRF shows the notice and keeps the passkey`.
  - Sign-in: the button reads "Entrar con huella" in es.
- [ ] **Step 2:** Run those tests; expect failures.
- [ ] **Step 3:** Implement; ARB keys for the new strings in four languages; replace "llave de acceso" on the unlock screen's es strings with "huella"; `flutter pub get` regenerates l10n. The passkey button still shows only when `unlockPasskeyOfferedProvider` says the phone can use passkeys.
- [ ] **Step 4:** Run `flutter analyze` and `flutter test` without goldens and the `stack` tag; update any golden the unlock screen has and say so in the report.
- [ ] **Step 5:** Update `apps/mobile/AGENTS.md`. Commit `feat(mobile): passkey-first unlock, the recovery key under more options`.

### Task 6: Screens map and the real-phone check

- [ ] Update the Figma screens map (web and phone unlock, web sign-in) with the Figma MCP; if it is not connected, write that in the PR body.
- [ ] Full checks: `pnpm lint`, `pnpm typecheck`, `pnpm test`, the web e2e, `flutter analyze`, `flutter test`.
- [ ] PR body lists the founder's real-phone check (after a phone build): sign in with the Google passkey (one touch, data open) and with the Proton Pass passkey (recovery-key field at once).
