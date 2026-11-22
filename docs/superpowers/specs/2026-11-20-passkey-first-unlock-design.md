# Passkey-first unlock (option A)

Draft for the founder's approval, 2026-11-20. Parent: `2026-11-08-end-to-end-encryption-design.md`
(section 4.1, passkey wraps) and `2026-11-15-phone-first-accounts-design.md`.

## Why

Since the switch day every account is encrypted. Opening the data on a new browser or phone today
leads with the recovery key: a long code the person typed once and should rarely need again. The
founder's words: the passkey is the main key to decrypt; the recovery key is the last resort and
belongs under "more options".

Two facts shape the design:

- A passkey can open the data only when its provider gives the WebAuthn PRF. Google Password
  Manager, iCloud Keychain (iOS 18, macOS 15), Windows Hello and security keys do. Proton Pass and
  1Password do not. The founder uses Proton Pass and stays there, so the no-PRF path must stay
  comfortable, not hidden.
- The web already opens the vault with the sign-in's PRF (`keepSignInPrf` / `takeSignInPrf`,
  e2e `a passkey unlocks with PRF`). The phone does not: `SessionController.signInWithPasskey`
  never asks for the PRF, so every passkey sign-in lands on the recovery-key screen and needs a
  second touch on "Use a passkey". The founder hit this with a Google passkey on 2026-11-20.

## Goals

1. **One touch.** Signing in with a PRF passkey opens the data with that same touch, on the web
   (already true) and on the phone (new).
2. **The unlock screen leads with what will work.** Passkey first, "from your phone" (the QR
   pairing) second, the recovery key under "More options".
3. **No dead ends for a passkey without PRF.** When the last passkey touched on this device gave no
   PRF, the unlock screen shows the recovery-key field at once, with one line saying why.
4. **The recovery key is easy to type and paste.** The field adds the dashes while typing and
   accepts a pasted key in any shape.
5. **Say it when a new passkey cannot open the data.** Adding a passkey without PRF tells the
   person, at that moment, that it signs in but does not open the data.

## Non-goals

- No change to the keys, the wraps, the API or the MCP. No `CHANGELOG.md` line.
- No account without a recovery key. The recovery key still exists and still works everywhere.
- No automatic passkey prompt when the unlock screen opens: the touch follows a tap.
- No removal of the recovery-key sign-in on the sign-in page; it only moves.

## Anti-goals

- A person with a no-PRF passkey must never see a screen whose main button cannot work for them
  without the fallback in sight.
- The PRF is never written to disk, never logged, and is zeroed after use, as on the web today.

## Approaches

- **A. Adaptive unlock screen, phone gets the web's one-shot PRF stash (chosen, my call).** The
  screen has three layouts, picked from what already happened. Small: it reuses the gate, the wraps
  and the existing buttons; the phone change mirrors `apps/web/app/local/prf.ts`.
- **B. Always hide the recovery key.** Simpler screen, but the founder and every Proton Pass or
  1Password user pays an extra tap on every new device, for ever. Rejected.
- **C. Detect PRF support per passkey on the server and choose the layout from it.** Needs a new
  field and an API change, and the server would learn which provider a person uses. Rejected: the
  wraps list (`GET /v2/keys`) already says whether any passkey wrap exists.

## Design

### 1. The unlock screen (web `Unlock.tsx`, phone `unlock_view.dart`)

The screen picks one of three layouts.

| Situation | Main | Below | Under "More options" |
|---|---|---|---|
| This device's last passkey touch gave no PRF | recovery-key field, with the line "Your passkey signs you in, but your password manager does not let it open your data." | "From another device" | "Use another passkey" (only if the account has a passkey wrap) |
| The account has a passkey wrap and this device supports passkeys | "Open with my passkey" | "From another device" | recovery-key field |
| Otherwise (no passkey wrap, or no passkey support) | "From another device" | — | recovery-key field |

When a layout would leave nothing above "More options" (the consent page has no pairing), the
recovery-key field is the main action and there is no disclosure.

- "From another device" is today's pairing (`onPair`), with today's labels on each platform (the
  phone's says "add this phone from another device"). It shows only where it shows today.
- "More options" is a disclosure, closed by default. It opens by itself when an attempt above it
  fails with `no_prf` or `no_passkey_wrap`, with today's error text.
- "Sign out" stays last, as today. The `removed` and `unverified` notices stay on top.
- The consent page reuses `Unlock` with its own title; it gets the same layouts.
- How the screen knows:
  - *no PRF on this device* (my call): a non-secret hint kept on the device, per user id, set
    whenever a passkey touch here (sign-in or unlock) gives no PRF, cleared when a passkey's PRF
    opens the data here. It survives a reload and a later return to Unlock. Web: `localStorage`
    (`wambito.*`); phone: a new pref. It holds a boolean, never a credential id. Sign-out keeps it;
    deleting the account's local data removes it.
  - *a passkey wrap exists* (my call): from the account's wraps (`GET /v2/keys`, which a signed-in
    session can read before the vault is open), not from Better Auth's passkey list that both
    sides use today: an account whose only passkey has no PRF has a passkey and no wrap, and must
    not get a main button that cannot work. When the wraps cannot be read, assume there is one.

### 2. Phone: the sign-in's PRF opens the vault

- `signInWithPasskey` and `signInWithAvailablePasskey` add the PRF extension to the request
  options (as `evaluatePrf` in `lib/local/prf.dart` does) and read `clientExtensionResults` from
  the assertion.
- The PRF waits in a one-shot, memory-only holder keyed by the user id, like
  `signInRecoveryKeyProvider`: taken once by the gate, zeroed after use, on sign-out, when it is
  another account's, and once the vault is open.
- `VaultGateDeps.takeSignInPrf` (already in `vault_gate.dart`, never wired) is wired in
  `vault_providers.dart`.
- A sign-in whose assertion has no PRF sets the marker of section 1.
- Both native sides already pass the PRF extension through `get` and `getAvailable`
  (`PasskeyChannel.swift`; Android forwards the request JSON), so no native change is expected.

### 3. The recovery-key field

- One field, as today (not seven boxes): it is what password managers and paste handle best.
- While typing, the text is shown upper case in groups, `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXX`:
  a dash appears after every fourth character; deleting over a dash removes the character before
  it; the caret keeps its place.
- A paste in any shape (lower case, spaces, no dashes, line breaks) is regrouped. Characters the
  key's alphabet does not have are dropped, except the ones the parser forgives (`O` for `0`, `I`
  and `L` for `1`, `packages/crypto/src/recovery.ts`), which are kept as typed.
- The submit button enables when the field holds a full key. The parser stays the judge.
- A "Paste" button sits in the field where the clipboard can be read (the phone; the web when
  `navigator.clipboard.readText` exists).
- One pure helper per side, `groupRecoveryKey(text)`, used by Unlock and by the sign-in's
  recovery-key form (`RecoveryKeySignIn.tsx`, the phone's email screen).

### 4. The sign-in page

- Web `SignIn.tsx`: email, the passkey button (shown as today, only where a passkey was used
  before; elsewhere the passkey comes through autofill) and the QR stay in sight. "Use my recovery
  key" moves under "More options", closed by default; opening it shows the field directly.
- Phone email screen: unchanged in structure (its recovery key is already a button to
  `/entry/recovery`); that screen's field gets section 3.

### 5. Adding a passkey without PRF

- Where a passkey is added on an encrypted account (web `PasskeysSection`, `PasskeyOffer`; phone
  `protectWithPasskey`, settings passkeys), a registration that ends without a PRF wrap shows, at
  once and not as a passing toast: "This passkey signs you in, but your password manager does not
  let it open your data. Keep your recovery key: you will need it on a new device."
- The passkey is kept. The row keeps saying "Does not open your data".
- A registration that says `enabled` without results still gets the second touch first, as today.

### 6. Copy

- es, en, it and pt (PT-PT). Spanish says "clave", never "llave", for the recovery key.
- My call: Spanish names the passkey "huella" on the unlock screen ("Abrir con mi huella"), as the
  web's sign-in page already does ("Entrar con huella"). Every string on the unlock screen that
  says "llave de acceso" (the button, `error_no_prf`, `error_no_passkey_wrap`, the notices) moves
  to "huella", on web and phone, and the phone's sign-in button "Usar passkey" becomes "Entrar con
  huella". The other languages keep their sign-in wording.

## Constraints

- Failing tests first. Everything in English in the repo.
- The Figma screens map changes (unlock, sign-in, both platforms): updated in the same change, or
  the PR says it was not.
- `apps/web/AGENTS.md` and `apps/mobile/AGENTS.md` are updated.
- A phone release is needed for the phone part; the founder signs it.

## Testing

- Web unit: `groupRecoveryKey` (typing, deleting, paste shapes, caret); the gate's marker; Unlock's
  three layouts and the self-opening disclosure (stories with play functions).
- Web e2e (`vault.spec.ts`, Chromium's virtual authenticator):
  - the existing `a passkey unlocks with PRF`, on the new labels;
  - new: a passkey with `hasPrf: false` signs in on a browser without the vault and lands on the
    unlock screen with the recovery-key field shown and the line; a pasted key without dashes
    opens the data.
- Phone unit: a passkey sign-in with a PRF leaves it for the gate and the gate opens with no
  screen; one without sets the marker; the holder is zeroed on sign-out and for another account;
  the unlock view's three layouts; `groupRecoveryKey`.
- On a real phone, by the founder: sign in with the Google passkey (one touch, data open) and with
  the Proton Pass passkey (recovery-key field at once).

## Left to the builder

- The names of the marker and the holder, and where the disclosure component lives.
- Whether `groupRecoveryKey` sits in `packages/crypto` (web) or beside Unlock.
- The exact copy in it and pt.
