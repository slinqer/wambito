# End-to-end encryption in Wambito

🚧 **Built, switching on soon.** The web, the phone and the assistants already work on encrypted accounts; every existing account moves over on one switch day, before the public release in Google Play and F-Droid. Until then your data travels encrypted (HTTPS) and the backups are encrypted, but the server can read your movements.

## How it works

| | | | | |
|:-:|:-:|:-:|:-:|:-:|
| <img src="brand/e2e/wambi-e2e-step1.webp" alt="Wambi locks receipts and coins in a chest on the phone; the key hangs from the phone." width="160"> | <img src="brand/e2e/wambi-e2e-step2.webp" alt="The locked chest travels between clouds; a snooper with a magnifying glass sees only scribbles." width="160"> | <img src="brand/e2e/wambi-e2e-step3.webp" alt="A server shelf full of locked chests, with no key." width="160"> | <img src="brand/e2e/wambi-e2e-step4.webp" alt="A fingerprint touch opens the chest on a laptop; a recovery card is the other way in." width="160"> | <img src="brand/e2e/wambi-e2e-step5.webp" alt="After the person taps allow, Wambi lends a temporary key to an assistant robot; when it is disconnected, Wambi changes the lock." width="160"> |
| **Locked on your device.** Each phone or browser encrypts your movements with a key only you hold. | **Unreadable on the way.** Anyone in the middle sees scribbles. | **The server keeps chests, not keys.** It stores and syncs encrypted records; its database and backups reveal no name, amount or note. | **Your key opens it anywhere.** A passkey touch, your recovery key, or approval from another of your devices. | **Assistants only if you say so.** Connecting Claude or ChatGPT lends them a key while connected; disconnecting changes the lock. |

## What the server still sees

Your email, how many records you have and when they change. Losing every passkey **and** the recovery key means losing the data: nobody else can open it, not even us. The design is in [`docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md`](superpowers/specs/2026-11-08-end-to-end-encryption-design.md).
