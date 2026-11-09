# Publishing on Google Play

The founder's guide for putting `com.wambito.app` on Google Play, published by Slinqer S.A.S. The build and the keys are in `release.md` ("The Play bundle"); this page covers the account, the one-time key handover and the Play Console forms, with a drafted answer for each. The answers must stay true to the privacy policy (`wambito.com/privacy`): change both together.

## Once: the account

1. **D-U-N-S number for Slinqer S.A.S.** It is free and takes up to 30 days, from Dun & Bradstreet, through the link Play Console gives during sign-up. The legal name and address must match the company's records exactly.
2. **Play Console organization account** (play.google.com/console, one-time fee), as Slinqer S.A.S. with the D-U-N-S number. Developer name `Wambito`, website `https://wambito.com`, contact email `hola@wambito.com`. Verify the website when Play asks. An organization account does not need the closed test of 12 testers for 14 days that new personal accounts need; if Play Console asks for it anyway, follow its own text.
3. **Payments profile**: none is needed, because the app is free and sells nothing.

## Once: the app and its keys

1. **Create the app**: name `Wambito`, default language Spanish (Latin America, `es-419`), App, Free. Accept the declarations.
2. **The upload key**: make it as `release.md` shows (`~/.wambito-signing/wambito-upload.p12`, alias `upload`) and back it up like the app key.
3. **Play App Signing with the app key** (Test and release → Setup → App integrity → App signing; Play offers it at the first upload too): choose **Use a different key**, then **Export and upload a key from Java keystore**. Download Play's `pepk.jar` and `encryption_public_key.pem` from that page and run, in a real terminal (PEPK asks for the passwords itself):

   ```sh
   export JAVA_HOME=~/development/jdk/jdk-17.0.21+9/Contents/Home
   cd ~/Downloads
   "$JAVA_HOME/bin/java" -jar pepk.jar --keystore="$HOME/.wambito-signing/wambito-release.p12" \
     --alias=lukitas --output=wambito-app-key.zip --include-cert --rsa-aes-encryption \
     --encryption-key-path=encryption_public_key.pem
   ```

   Upload `wambito-app-key.zip` (encrypted for Google, only Play can open it), then delete it. Then upload the **upload certificate**:

   ```sh
   "$JAVA_HOME/bin/keytool" -export -rfc -keystore ~/.wambito-signing/wambito-upload.p12 \
     -alias upload -file ~/Downloads/wambito-upload-cert.pem
   ```

   App integrity then shows two certificates: **App signing key** with the SHA-256 in `ANDROID_CERT_SHA256` (the one `release.sh` prints, `59:45:00:FD:…`), and **Upload key** with the one in `UPLOAD_CERT_SHA256.txt`. If the app signing one differs, stop: something else was uploaded.

Because Play signs with the app key, App Links and passkeys work for the Play build with no change to `ANDROID_CERT_SHA256`, and a phone with the APK from GitHub can later update from Play (with the next release: `release.md`).

## The store listing

From `apps/mobile/fastlane/metadata/android/<locale>/`: `title.txt`, `short_description.txt`, `full_description.txt`, `images/icon.png` (512×512, in `en-US`), `images/featureGraphic.jpg` (1024×500) and the six `images/phoneScreenshots/*.jpg` (1080×1920). The default listing is `es-419`; add the translations (Main store listing → Manage translations) for `es-ES`, `en-US`, `it-IT` and `pt-PT`. Play picks a listing by the phone's language, not its country, so the money in each set of pictures is the one its language's people mostly use: `es-419` pesos (shot as `es-CO`), `es-ES`, `it-IT` and `pt-PT` euros, `en-US` dollars. `scripts/check-fastlane.sh` checks all of it.

To make the pictures again (after a change to the screens the pictures show), with the root dev stack up and the AOSP emulator running, never a real phone:

```sh
apps/mobile/tool/store_shots/run.sh            # raw screenshots, all five languages, ~4 min each
node apps/mobile/tool/store_shots/compose.cjs  # the listing images, with Wambi and the captions
apps/mobile/scripts/check-fastlane.sh
```

`run.sh` signs a guest in on the emulator, seeds invented movements and budgets through the API, and pins the emulator's language and time zone per locale (the currency follows them). `compose.cjs` holds the captions (`WORDS`) and frames each screenshot on the night plum with a pose from `docs/brand/wambi-store-*.webp`; the feature graphic is Wambi and the logo, no words, the same in every listing. Look at all the images before committing them: the founder approves a new set.

- App category: **Finance**. Tags: budgeting, expense tracker.
- Contact email `hola@wambito.com`; website `https://wambito.com`.
- Privacy policy: `https://wambito.com/privacy`.

## App content (Policy and programs → App content)

- **Privacy policy**: `https://wambito.com/privacy`.
- **App access**: "All or some functionality is restricted" is not needed: the app starts without an account (guest, "Probar sin correo"). Add an instruction for reviewers: "Tap 'Probar sin correo' on the first screen to use the app as a guest. Automatic capture (Settings → Captura automática) reads notifications from Revolut and Google Wallet only, and needs one of those apps with a payment to show anything."
- **Ads**: No, the app contains no ads.
- **Content rating** (IARC questionnaire): category **All other app types** (utility, productivity). No violence, sexuality, language, controlled substances or gambling; users do not interact or exchange content with each other; no location sharing; no digital purchases. The expected rating is the lowest (PEGI 3 / Everyone).
- **Target audience**: 18 and over only. Not designed for children; no appeal to children.
- **News app**: No. **Government app**: No. **Health**: none. **COVID-19**: not a COVID app.
- **Financial features**: the app offers **personal finance: budgeting / expense tracking**. It offers none of: loans, banking, payments or transfers, crypto, insurance, investing, credit scores. It does not hold or move money.
- **Account deletion**: the app lets people create an account, so Play asks for a link: `https://wambito.com/delete-account`, and deletion is also in the app (Settings → Eliminar mi cuenta).
- **Permissions declarations**: none of the declared-permission groups apply (no SMS, call log, location, all-files access, accessibility, exact alarms, foreground service or package visibility). The notification listener needs no declaration form, but its prominent disclosure must stay in the app (`lib/capture_auto/how_capture_works.dart`, the footer above «Activar acceso», `autoCaptureHowDisclosure` in the ARBs): what is read (the notifications of the apps the person turns on) and what leaves the phone (only the amount, merchant, date and app), right before the button that opens Android's access screen. `test/l10n/capture_copy_test.dart` holds it to that in all four languages; a reviewer can see it with automatic capture switched on for the first time.

### Data safety

Data is encrypted in transit (HTTPS) and people can ask for it to be deleted (in the app, or at the deletion page). Nothing is shared with third parties: the server, the backups (Cloudflare R2, encrypted) and email delivery are service providers acting for Wambito, which Play does not count as sharing. Nothing is collected for analytics, ads or personalisation.

| Data type | Collected | Why | Optional |
|---|---|---|---|
| Personal info → Email address | yes | App functionality, Account management | yes (guests have none) |
| Personal info → User IDs | yes (the account id) | App functionality, Account management | no |
| Financial info → Purchase history | yes: transactions the person enters, and the amount, merchant, date and app taken from a bank notification by automatic capture | App functionality | yes |
| Financial info → Other financial info | yes: categories, budgets, recurring payments | App functionality | yes |
| Device or other IDs | yes: the IP address and browser or app name stored with each sign-in session | Fraud prevention, security | no |

Not collected, because it is processed only on the phone and never sent: **Audio** (voice is transcribed on the phone; the audio stays in memory and is never stored or sent), and the **text of notifications** (only the transaction taken from it is sent, listed above). No location, contacts, photos, files, web history, crash logs or diagnostics are collected.

The voice models are downloaded from the project's GitHub releases when the person asks for them. They are data (model weights), not code, so Play's rule on downloaded code does not apply; the runtime is in the app.

## Each release

1. On the tagged release commit, `release.sh --play` (`release.md`). The first bundle is `mobile-v1.0.2`: earlier tags have no `--play`, nor the disclosure above. It writes the APKs and `wambito-<version>.aab`.
2. **Internal testing** first (Test and release → Testing → Internal testing): create a release, upload the `.aab`, paste the release notes from `fastlane/metadata/android/<locale>/changelogs/<APK code>.txt` (the AAB's own code, base × 10, has no changelog file of its own), add testers by email list, roll out.
3. Install from the testers' link on a phone, and check: sign in by magic link (the link opens the app), a passkey, voice (and the precise model download), the widget, automatic capture's disclosure.
4. Promote the same release to **Production** (staged rollout if wanted). The first production review takes a few days.
