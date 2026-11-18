# Quick Device Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Removing a device takes one confirmation and no recovery key, "Change keys" is a separate action on both clients, and signing out deletes the device's own wrap so the devices list has no leftovers.

**Architecture:** Both clients call the existing `DELETE /v2/keys/{id}` in two cases: to remove another device, and to delete their own wrap right before sign-out. Removal no longer rotates. The rotation stays behind "Change keys", which the web already has and the phone gains. The API does not change.

**Tech Stack:** React Router web app (Vitest, Storybook play tests), Flutter phone app (flutter_test, Riverpod).

**Spec:** `docs/superpowers/specs/2026-11-18-quick-device-removal-design.md`

## Global Constraints

- No API change, no `CHANGELOG.md` line. The only new client call is `DELETE /v2/keys/{id}` (204; 404 means already gone and counts as done; 409 `recovery_required` never happens for a device).
- Copy in es, en, it, pt (web `app/i18n/messages/app.{es,en,it,pt}.json`, phone `lib/l10n/app_{es,en,it,pt}.arb`). PT-PT ("telemóvel"), no money slang in it/pt (`messages.test.ts` enforces it). Spanish and English are fixed below; write it and pt in the same voice.
- The phone asks the screen lock before removal (`confirmSensitive`), as today. The web asks for nothing more than the sheet's "Remove" button.
- A plain account changes nothing.
- The own-wrap delete before sign-out: only when the account is `preview`, its own device wrap id is known, and (phone) its vault is not held (`listVaultHolds()`). Bounded by a short timeout (web 3 s; phone `signOutWait`). Any failure or timeout is ignored, and the sign-out goes on as today.
- Write the failing test first. Stage by path. Commits `feat(web): …` / `feat(mobile): …`, lowercase. Never a `Co-Authored-By` line.
- Whoever changes a flow updates its `AGENTS.md` lines (`apps/web/AGENTS.md`, `apps/mobile/AGENTS.md`) and, for phone copy that has a web twin, `docs/mobile/parity.md`.

Fixed copy:

| Key idea | es | en |
|---|---|---|
| Sheet title | Quitar {device} | Remove {device} |
| Sheet body | Este dispositivo dejará de entrar a tu cuenta y no recibirá nada nuevo. | This device will be signed out of your account and won't receive anything new. |
| Button | Quitar | Remove |
| Busy | Quitando… | Removing… |
| Done toast | {device} ya no tiene acceso. | {device} no longer has access. |
| After "That wasn't me" (phone only) | Si alguien más tuvo tu llave, cámbiala: lo que guardes desde ahora no lo podrá leer. | If someone else had your key, change it: they won't be able to read anything you save from now on. |
| That suggestion's button | Cambiar llaves | Change keys |

## Review Focus

1. Removing the device that is this browser or phone is still impossible (the list never offers it).
2. A removal answered 404 (removed meanwhile from another device) reads as done, not as an error.
3. Offline removal says so and leaves the row; nothing is half-done.
4. Sign-out with no connection still signs out at once (the bounded wait), on both clients.
5. A phone sign-out while a merge or adoption holds the vault keeps that vault's wrap.

---

### Task 1: Web: remove a device without rotating

**Files:**
- Modify: `apps/web/app/features/settings/security.ts` (the `SecurityApi` gains `removeDevice`, live version)
- Modify: `apps/web/app/features/settings/RemoveDeviceSheet.tsx` (confirm-only sheet)
- Modify: `apps/web/app/features/settings/SecuritySection.tsx` (wiring, reload after removal)
- Modify: `apps/web/app/i18n/messages/app.{es,en,it,pt}.json` (copy above; remove the removal sheet's recovery-key keys nothing uses any more)
- Test: `apps/web/app/features/settings/security.test.ts`, `apps/web/app/features/settings/Security.stories.tsx`

**Interfaces:**
- Produces: `SecurityApi.removeDevice(id: string): Promise<void>`. It rejects with an error whose `codeOf` is `offline` without a connection, or `failed`. 404 resolves.
- `RemoveDeviceSheet` props: drop everything about the recovery key and passkeys (`hasPasskeys` …); keep `device`, `security`, `onClose`, plus `onRemoved(device)`.

- [ ] Write failing tests: `security.test.ts` "removeDevice sends DELETE /v2/keys/{id} and nothing to /v2/keys/rotate", "a 404 resolves", "no connection rejects with offline". Story play tests: `RemoveDevice` taps "Quitar", expects `removeDevice` called once with the row's id, then the toast "{device} ya no tiene acceso." and the row gone; `RemoveDeviceOffline` shows the offline line and keeps the row.
- [ ] Run them and watch them fail.
- [ ] Implement. Delete the rotate-for-removal path from the sheet. The web's "Change keys" (`ChangeKeysSheet`) is untouched.
- [ ] `pnpm --filter @wambito/web test` (unit and storybook projects for the touched files), `pnpm --filter @wambito/web typecheck`, `pnpm lint`.
- [ ] Update the removal lines in `apps/web/AGENTS.md`. Commit `feat(web): remove a device with one tap, without changing the keys`.

### Task 2: Web: sign-out deletes this browser's device wrap

**Files:**
- Modify: `apps/web/app/local/vault-session.ts` (new export), `apps/web/app/features/home/use-sign-out.ts` (`liveSignOut` calls it before `authClient.signOut()`)
- Test: `apps/web/app/local/vault-session.test.ts` (and the sign-out hook's test if one exists)

**Interfaces:**
- Produces: `forgetOwnDeviceWrap(options?: { timeoutMs?: number }): Promise<void>` in `vault-session.ts`: with an active preview vault whose meta `deviceWrapId` is set, `DELETE /v2/keys/{that id}` within `timeoutMs` (default 3000). Never rejects.

- [ ] Write failing tests: "sends DELETE for the own wrap before the session ends", "does nothing without an active vault or without a deviceWrapId", "a hanging or failing DELETE resolves within the timeout and the sign-out still runs".
- [ ] Watch them fail; implement; rerun.
- [ ] Typecheck, lint; update `apps/web/AGENTS.md` (sign-out line). Commit `feat(web): signing out deletes this browser's device wrap`.

### Task 3: Phone: remove a device without rotating, and "Change keys"

**Files:**
- Modify: `apps/mobile/lib/settings/security/security_api.dart` (`removeDevice`)
- Modify: `apps/mobile/lib/settings/security/remove_device_sheet.dart` (confirm-only)
- Create: `apps/mobile/lib/settings/security/change_keys_sheet.dart` (the recovery-key part the removal sheet had: typed key or a new key through `RecoverySetupPage`, with `rotate(remove: [], …)`, then `reloadKeys()`; its comments say why the commit is retried with the same prepared rotation and how a prepared rotation that is given up on is forgotten)
- Modify: `apps/mobile/lib/settings/security/security_section.dart` (a "Cambiar llaves" row, the web's twin; preview accounts only), `apps/mobile/lib/settings/security/signin_notice.dart` (after a removal from "That wasn't me", the done step shows the suggestion and opens `ChangeKeysSheet`)
- Modify: `apps/mobile/lib/l10n/app_{es,en,it,pt}.arb`
- Test: `apps/mobile/test/settings/security/` (the removal sheet's tests, a new `change_keys_sheet_test.dart`, the notice's tests)

**Interfaces:**
- Produces: `SecurityApi.removeDevice(String id)` → `Future<void>`; 404 completes; failures throw with codes `offline` / `failed`, the same codes the sheet shows today.
- `ChangeKeysSheet.open(BuildContext, {required SecurityApi security})` → `Future<RotateResult?>`.

- [ ] Write failing tests: removal calls `removeDevice` once after the screen lock and never `rotate`; 404 reads as done; offline keeps the sheet with the offline line. Change keys rotates with `remove: []` using the typed key (and the new-key path). The notice's removal shows the suggestion, and its button opens Change keys.
- [ ] Watch them fail; implement; rerun. Run `flutter analyze` and `flutter test --exclude-tags golden,stack` for the touched folders.
- [ ] Update `apps/mobile/AGENTS.md` and `docs/mobile/parity.md` for the removal sheet and the new "Change keys". Commit `feat(mobile): remove a device with the screen lock only; change keys on its own`.

### Task 4: Phone: sign-out deletes this phone's device wrap

**Files:**
- Modify: `apps/mobile/lib/api/session.dart` (`signOut`, before `_auth.signOut(token)`)
- Test: the session sign-out tests under `apps/mobile/test/api/`

**Interfaces:**
- Consumes: `KeyStorage.deviceWrapId(userId)`, `listVaultHolds()`, the account's mode (preview).
- Produces: no new public API. `signOut` deletes `/v2/keys/{deviceWrapId}` first, within `signOutWait`, ignoring every failure.

- [ ] Write failing tests: "a preview account's sign-out deletes its own device wrap before ending the session"; "no DELETE for a plain account, without a wrap id, or while the vault is held"; "an offline DELETE does not delay the sign-out past signOutWait".
- [ ] Watch them fail; implement; rerun with `flutter analyze`.
- [ ] Update `apps/mobile/AGENTS.md` (sign-out). Commit `feat(mobile): signing out deletes this phone's device wrap`.
