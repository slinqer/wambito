# Releasing the Android app

How the founder builds the signed APKs, what the version numbers mean, and what CI does. The signing key lives only on the founder's Mac: never in the repo, never in CI, never in a log (spec section 8). Toolchain setup is in `setup.md`.

## The version scheme

`versionName` comes from a `mobile-vX.Y.Z` tag. `versionCode` is derived from it, so each release is above the one before, and the two split APKs of a release differ:

| | |
|---|---|
| versionName | `X.Y.Z`, from the tag |
| base code | `X*10000 + Y*100 + Z` (X up to 9999, Y and Z up to 99; releases start at 0.1.0) |
| versionCode | `base * 10 + ABI digit`: 0 universal, 1 `armeabi-v7a`, 2 `arm64-v8a` |

For `mobile-v1.0.0`: base 10000, so `armeabi-v7a` is 100001 and `arm64-v8a` is 100002. Flutter's own scheme (`ABI * 1000 + code`) is switched off (`force-version-code-ignoring-abi` in `android/gradle.properties`) because it does not rise from one release to the next. The scheme lives in `scripts/release-lib.sh` (tested by `scripts/test-release.sh`) and in `android/app/build.gradle.kts`; `release.sh` reads each APK's manifest back and fails if the two disagree.

With no tag, `release.sh` makes a dev build: `0.0.0-dev.<commit>`, base code 1 (11 and 12 for the splits), below every release. `pubspec.yaml`'s `0.0.0-dev+1` is what any plain `flutter build` gets.

Pre-release suffixes (`-rc1`) are refused: tags are `mobile-vX.Y.Z` and nothing else.

## The signing key (once)

The keystore lives in `~/.wambito-signing/wambito-release.p12`. Its alias stays `lukitas`: the alias is written inside the key, and changing it means re-keying, which would stop every installed copy from updating.

Use JDK 17's `keytool` (setup.md puts it in `~/development/jdk`). The keystore goes outside every repository; keytool asks for the password, so it never touches a shell history. 
**Back it up before you hand out a single APK.** If the keystore or its password is lost, every installed copy of the app can never be updated: Android refuses an update signed with a different key, so people would have to uninstall (losing a guest's data on the phone's side) and install again, and `ANDROID_CERT_SHA256` and the passkeys tied to it would have to change. Nobody, including F-Droid, can recover it.

- Keep an encrypted copy of the `.p12` file and its password in your password manager (as an attachment and a note), and a second copy offline (an encrypted disk image on a USB drive that lives somewhere else).
- Test the copy once: `"$JAVA_HOME/bin/keytool" -list -keystore <copy> -alias lukitas` should ask for the password and print the key's `SHA256` fingerprint. Write that fingerprint next to the backup; it must match what `release.sh` prints.
- Never put the keystore, its password or a `key.properties` in the repository, a chat, an email or CI (`apps/mobile/.gitignore` and `android/.gitignore` refuse `*.p12`, `*.pfx`, `*.jks`, `*.keystore` and `key.properties`, but keep it outside the checkout anyway).

```sh
export JAVA_HOME=~/development/jdk/jdk-17.0.21+9/Contents/Home
mkdir -p ~/.wambito-signing && chmod 700 ~/.wambito-signing
"$JAVA_HOME/bin/keytool" -genkeypair \
  -keystore ~/.wambito-signing/wambito-release.p12 -storetype PKCS12 \
  -alias lukitas -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Wambito, O=<your name>"
chmod 600 ~/.wambito-signing/wambito-release.p12
```

### Moving a key made under the old folder name

A key made before the rename sits in `~/.lukitas-signing/lukitas-release.p12`. Move it once; it is the same key, so the backups in the password manager and offline stay as they are:

```sh
export JAVA_HOME=~/development/jdk/jdk-17.0.21+9/Contents/Home
mkdir -p ~/.wambito-signing && chmod 700 ~/.wambito-signing
cp ~/.lukitas-signing/lukitas-release.p12 ~/.wambito-signing/wambito-release.p12
chmod 600 ~/.wambito-signing/wambito-release.p12
"$JAVA_HOME/bin/keytool" -list -keystore ~/.wambito-signing/wambito-release.p12 -alias lukitas
```

Only when that prints the same `SHA256` fingerprint as the one written next to the backup, remove the old folder: `rm -r ~/.lukitas-signing`.

## Building the first APK

`release.sh` reads four environment variables and nothing else. They are never printed (tracing is switched off in the script, the signing tool gets the passwords through its environment and not its arguments, and anything it prints is scrubbed of them), and Flutter and Gradle never see them: the APKs are built unsigned and then signed with `apksigner`.

| Variable | |
|---|---|
| `WAMBITO_KEYSTORE` | path of the keystore |
| `WAMBITO_KEY_ALIAS` | the key's alias (`lukitas` above) |
| `WAMBITO_KEYSTORE_PASSWORD` | the keystore's password |
| `WAMBITO_KEY_PASSWORD` | the key's password; leave it unset for a PKCS12 keystore like the one above (same as the keystore's) |

Do the key move below (its own section) once, before the first build from these instructions. Until the Mac folder is moved, `cd` into the current checkout instead of `~/projects/wambito`.

**Precondition for any `mobile-v*` tag: the Canary model must be published.** Eligible phones download it from the release `voice-models-v2`, so that release must exist with `sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8.zip` (es/en) and `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.zip` (it/pt), each built by ONE run of `apps/mobile/scripts/package-canary.sh` (`--model parakeet` for the second), whose sizes and SHA-256 equal the values pinned in `apps/mobile/lib/capture/models_download.dart` (Canary: 150137764 bytes, SHA-256 `65bf6fb27f22c506b217d1847c2a61ad0d8a734eed6a6842d4e735dfed10776b`; Parakeet: 477666406 bytes, SHA-256 `f7f4d4f9a04ef10d77a99eb9ad3c1a616393c031cbf0232febfac51dc3bd937d`). Otherwise every eligible phone gets a 404 (or a failed check) on the precise model. Check it before tagging: `gh release view voice-models-v2 --repo slinqer/wambito` (each asset's size, and its digest against the SHA-256 above). If a rebuilt zip differs, the pins change in the app first, never the other way round.

Before this, on `main`: for each release after `mobile-v1.0.0`, add and commit the new `<versionCode>.txt` changelogs (both codes, all four locales, `scripts/check-fastlane.sh` checks them) and push `main`. The release commit below is cut from `main`, and F-Droid reads the changelogs at the tag, so they must already be there.

```sh
cd ~/projects/wambito
git checkout main && git pull
git checkout --detach                  # the release commit sits on top of main, never merged into it
sed -i '' 's/^version: .*/version: 1.0.0+10000/' apps/mobile/pubspec.yaml   # X.Y.Z+<base code>
git commit -m "chore(mobile): release 1.0.0" -- apps/mobile/pubspec.yaml
git tag mobile-v1.0.0                  # the release; the script builds the commit the tag points at
                                       # (push the tag once the APK is checked: F-Droid reads tags)
export PATH="$HOME/development/flutter/bin:$PATH"
export WAMBITO_KEYSTORE=~/.wambito-signing/wambito-release.p12
export WAMBITO_KEY_ALIAS=lukitas
printf 'Keystore password: '; read -rs WAMBITO_KEYSTORE_PASSWORD; echo; export WAMBITO_KEYSTORE_PASSWORD
apps/mobile/scripts/release.sh
```

(The F-Droid changelogs in `apps/mobile/fastlane/metadata/android/*/changelogs` are named for `mobile-v1.0.0`'s version codes, 100001 and 100002. For another first version, rename them; `release.sh` warns when a tagged build has none. For each later release, add `<versionCode>.txt` for both codes in all four locales, on `main`, before the release commit.)

Once the APK is checked, publish the tag (it is local until then): `git push origin mobile-v1.0.0`. For the first F-Droid submission, push the tag before opening the fdroiddata merge request (`apps/mobile/fdroid/MERGE_REQUEST.md`), which needs it to exist upstream. For a later release, if Flutter, the NDK, the SDK platform, a srclib revision or `build-native-deps.sh`'s flags changed since the last one, open a merge request on fdroiddata with the updated recipe first: its copy is the live one and auto update only bumps versions (`docs/mobile/fdroid.md`, "Changing the recipe after F-Droid publishes").

What it does: `flutter clean`, an unsigned `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64` with `--build-name` and `--build-number` from the tag, then for each ABI: checks the alignment (4 bytes, and 16 KB for the native libraries), signs with `apksigner`, verifies the signature (v2 at least, not the debug key, the same certificate for both APKs), compares the manifest's version with the scheme, and runs `check-permissions.sh` on the signed APK. It compares the certificate with the one `keytool` reads from the keystore, and writes everything to `apps/mobile/dist/<versionName>/` (git-ignored):

```
wambito-1.0.0-arm64-v8a.apk   wambito-1.0.0-armeabi-v7a.apk   SHA256SUMS   ANDROID_CERT_SHA256.txt
```

The tagged commit, and only it, carries the release's version in `apps/mobile/pubspec.yaml`: `version: X.Y.Z+<base code>` (`1.0.0+10000` for `mobile-v1.0.0`). F-Droid's `checkupdates` finds a new `mobile-v*` tag and reads the version from that line (`UpdateCheckData` in `apps/mobile/fdroid/com.wambito.app.yml`); `release.sh` refuses a tag whose pubspec says anything else. `main` keeps `0.0.0-dev+1` (`scripts/test-release.sh` checks it), so go back with `git checkout main` after the release.

A tagged build needs a clean working tree (`--allow-dirty` overrides); `--tag` names the tag to build and must point at HEAD; `--no-clean` skips `flutter clean` while iterating; `--out` changes `dist`.

The last line it prints is the certificate's SHA-256 as `ANDROID_CERT_SHA256` takes it, uppercase pairs with colons, 32 of them:

```
ANDROID_CERT_SHA256=AB:CD:...:EF
```

Put it in `deploy/personal/.env`, run `deploy/personal/up.sh`, then `deploy/personal/smoke.sh` (see `deploy/personal/README.md`, "The Android app"). The web container writes `/.well-known/assetlinks.json` from it, which is what lets the app open magic links and use passkeys; the API derives the passkey origin (`android:apk-key-hash:...`) from the same value. When F-Droid signs its own build later, list both fingerprints, comma-separated.

Install on a phone: `adb install apps/mobile/dist/1.0.0/wambito-1.0.0-arm64-v8a.apk` (nearly every phone since 2017; `armeabi-v7a` is for 32-bit ARM phones). Each APK is about 30 MB; the universal APK would be about 60 MB, about 19 MB of it Vosk's native library for ABIs no phone needs here.

Publish the APKs as a GitHub release on the tag (the landing's "Descargar para Android" links there), from the repo root:

```bash
d=apps/mobile/dist/X.Y.Z
gh release create mobile-vX.Y.Z --repo slinqer/wambito --verify-tag --latest \
  --title "Wambito X.Y.Z (Android)" --notes-file <notes.md> \
  $d/wambito-X.Y.Z-arm64-v8a.apk $d/wambito-X.Y.Z-armeabi-v7a.apk $d/SHA256SUMS $d/ANDROID_CERT_SHA256.txt
```

The notes are the `en-US` arm64 changelog, which APK to pick, and the certificate's SHA-256. Once the release is up, and not before (the link would 404), raise `ANDROID_VERSION` in `apps/web/app/features/landing/links.ts` and the two URLs in `apps/web/e2e/landing.spec.ts` and `landing-only-app.spec.ts`; merging that deploys the landing. Mark only `mobile-v*` releases as latest, never `voice-models-*`.

## Reproducible builds

`scripts/check-reproducible.sh` builds the unsigned release APKs twice from clean on the same commit and compares them with `sha256sum` (and `diffoscope`, if installed, when they differ); `--also-at <new dir>` adds a build from a fresh clone at another path. The result and what it means for F-Droid are in `fdroid.md`.

## CI

`.github/workflows/ci.yml`, on pull requests that touch `apps/mobile` or what its generated code depends on (the `mobile-changes` filter). The jobs `mobile` and `mobile-emulator` are not required checks yet.

- `mobile`: `flutter analyze`; `flutter test --exclude-tags golden`; the generated-code checks; `check-no-google.sh` and its probes; a debug build; the Kotlin unit tests (`./gradlew :app:testDebugUnitTest`, Robolectric); `test-release.sh`; `check-fastlane.sh`; a release build with `check-permissions.sh` and `check-licenses.sh`; and finally `release.sh` itself with a throwaway key made on the runner.
- `mobile-emulator`: the dev stack from compose, on the real clock (no `E2E_NOW`: the emulator's clock is real and every test makes its own data from the device's today) and `scripts/run-integration-tests.sh` on an x86_64 API 36 emulator (`reactivecircus/android-emulator-runner`, AOSP image, KVM), with the AVD and Gradle caches kept between runs.
- Signed releases are never built in CI: that stays a later decision.

The integration tests locally: see "Integration tests against the dev stack" in `setup.md`, or `apps/mobile/scripts/run-integration-tests.sh` once an emulator is running.
