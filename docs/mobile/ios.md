# iOS: App Store Connect and TestFlight

One-time setup for the person who owns the Apple Developer account (a paid team), then what each
release does. The build is `.github/workflows/ios-release.yml`; the pull-request checks are the `ios`
job in `ci.yml`. The Android side is `release.md`.

## One-time setup

1. **App ID.** In the Apple Developer portal, Certificates, Identifiers & Profiles, make an
   explicit App ID with bundle id `com.wambito.app` and these capability: Associated Domains
   (the app needs nothing else).
2. **Distribution certificate.** Make an Apple Distribution certificate (CSR from Keychain Access),
   install it, then export it from Keychain Access as a `.p12` with a password. Encode it:
   `base64 -i dist.p12 | pbcopy`.
3. **App Store Connect API key.** Users and Access, Integrations, App Store Connect API: make a
   team key with the **App Manager** role. Note the Key ID and the Issuer ID; download the `.p8`
   once (Apple shows it only once).
4. **The app record.** In App Store Connect make the app: bundle id `com.wambito.app`, name
   Wambito, primary language, SKU of your choice.
5. **Secrets.** In the GitHub repository, Settings, Environments, make `app-store` (restrict it to
   tags `mobile-v*`) and add these secrets:

   | Secret | Value |
   |---|---|
   | `IOS_TEAM_ID` | the 10-character team id (Developer portal, Membership details) |
   | `IOS_DIST_CERT_P12` | the base64 text of the `.p12` from step 2 |
   | `IOS_DIST_CERT_PASSWORD` | the `.p12`'s password |
   | `ASC_KEY_ID` | the API key's Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID (top of the API keys page) |
   | `ASC_KEY_P8` | the whole contents of the `.p8` file, header and footer lines included |

6. **The web server.** Universal Links and passkeys need the team id in the apple-app-site-association
   file: set `IOS_TEAM_ID` in the VPS's `deploy/personal/.env` (see `.env.example`) and redeploy.
   Without it the file is still served, with no app ids, and the links open in Safari.
7. **Local builds.** Copy `apps/mobile/ios/Flutter/Signing.xcconfig.example` to
   `Signing.xcconfig` (same folder, git-ignored) and put your team id there. The team id never goes
   in the repo: `scripts/check-ios-signing.sh` fails CI on one in the Xcode project.

## A release

1. Release as in `release.md`: tag `mobile-vX.Y.Z` on the release commit and push the tag (pushing is what starts the workflow, so do it after the Android APK is checked). The tagged
   commit's `pubspec.yaml` version (`X.Y.Z+<base code>`) is the iOS version and build number; App
   Store Connect refuses a build number it has already seen.
2. The `iOS release` workflow archives, exports and uploads the build with the API key. Xcode makes
   the provisioning profile itself (automatic signing). Nothing is printed of the secrets, and the
   temporary keychain and key file are removed at the end, even if a step fails.
3. In App Store Connect, wait for the build to finish processing (a few minutes; an email says
   when). Open TestFlight, add testers (internal ones need no review), and answer the export
   compliance question if it asks (below).
4. To publish: App Store tab, the version, select the build, fill the listing, Submit for Review.
   Review and release are by hand.

## Answers App Store Connect asks

- **Encryption (export compliance).** The app sets `ITSAppUsesNonExemptEncryption` to `NO`, so the
  question is skipped on upload. Answer it the same way if it is ever shown: the app uses only
  encryption built into the operating system and standard protocols (HTTPS) and its own
  end-to-end encryption with published standard algorithms to protect the user's own data, which is
  exempt. No export documents are filed. If the encryption changes beyond this, review the answer
  first.
- **App Privacy.** Match `apps/mobile/ios/Runner/PrivacyInfo.xcprivacy`: no tracking, no tracking
  domains; collected data, both linked to the user, not used for tracking, purpose App
  Functionality: **Financial Info, Other Financial Info** (the movements) and **User Content, Other
  User Content** (notes and categories). Nothing else is collected. The data is stored encrypted
  end to end; say so in the privacy policy link, which is the web app's.
- **Required-reason APIs.** UserDefaults (reason CA92.1) and file timestamps (reason C617.1) are
  declared in the same file; no answer is needed in the console.

## When it fails

- `No profiles for 'com.wambito.app'` or a signing error: the API key's role is not App Manager,
  the App ID is missing, or `IOS_TEAM_ID` is wrong.
- `No signing certificate` at export: the `.p12` is not an Apple Distribution certificate for the
  same team, or its password is wrong.
- Upload rejected for a build number: raise the version in `pubspec.yaml` and tag again.
