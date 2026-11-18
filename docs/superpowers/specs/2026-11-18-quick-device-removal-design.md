# Quick device removal and sign-out without leftover devices

Approved by the founder on 2026-11-18, after the phone-first device test on an Android phone.

## Why

The device test found two things that felt wrong:

- **Duplicates.** Settings → Devices showed "Chrome on macOS" more than once. Each web sign-in
  makes a new device wrap. Signing out deletes the browser's keys but leaves its wrap on the
  server, so the list keeps a device that can never unlock again.
- **Too heavy.** Removing a device asked for the screen lock, then for the recovery key (or a new
  one to write down). Removal rotates the data key (stage 2b Ruling 2, 3b section 7.6, D15), and a
  rotation has to re-wrap the recovery wrap, which needs the recovery key.

## Decision (the founder's, from three options)

"Fingerprint only":

1. **Remove = confirm and done.**
   - The phone asks for the screen lock (`confirmSensitive`), as today. The web asks for a tap on
     "Remove" in the sheet.
   - Then the client calls `DELETE /v2/keys/{id}`. The route already exists: it deletes the wrap and
     ends the session that registered it. No rotation and no recovery key.
   - The removed device can no longer sign in or pull anything.
2. **Changing the keys is separate.**
   - On the web it already exists: Settings → Security → "Change keys".
   - The phone gets the same action, which rotates with nothing removed and the recovery key typed,
     or a new recovery key.
   - After a removal that came from "That wasn't me" (the new-device notice), the done view
     suggests changing the keys. A plain removal does not.
3. **Sign-out removes its own device wrap.**
   - Right before ending the session, web and phone call `DELETE /v2/keys/{own id}`, best effort
     and briefly bounded. Offline, the sign-out goes on; the leftover row can be removed from the
     list.
   - Only for an encrypted (`preview`) account whose own wrap id is known. Never for a vault that
     is held (merging, orphaned, provisional): that vault keeps its wrap.
   - A session that only expired (a 401) keeps its wrap, as today, so signing in again unlocks
     without the recovery key.

## Trade-off accepted

A removed device that had copied the data key could read ciphertext obtained later outside the
API (a server leak). Bitwarden and 1Password accept the same. "Change keys" closes it, and the
"That wasn't me" path suggests it.

## Not in this change

- No API change: `DELETE /v2/keys/{id}` and `POST /v2/keys/rotate` stay as they are, so no
  `CHANGELOG.md` line.
- No cleanup of existing leftover device wraps. They are only on test accounts, and a blanket
  delete could hit a phone whose session expired.
- Rotation code (`rotateKeys`, the web's `rotateKeys`) stays; it now serves "Change keys" only.

## Approaches considered

- **Fingerprint only (chosen):** one step; key change separate.
- **Fingerprint, then an optional key change:** the same, plus a question after every removal.
  Rejected: the question comes back every time.
- **Keep the rotation:** safest, but the heavy step the founder noticed.
