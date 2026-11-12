# apps/mobile: the phone app (Flutter, Dart package `wambito`)

Android and iOS, both `com.wambito.app`. No Play Services or Firebase (`scripts/check-no-google.sh`);
deps pinned, free-licensed (`scripts/check-licenses.sh`). Setup, emulator, JDK 17:
`docs/mobile/setup.md`. Release and signing: `docs/mobile/release.md`; iOS: `docs/mobile/ios.md`.
iOS is the base only (see "iOS" below): no automatic capture, widgets or voice yet.

## Dart entry points (`lib/`)

- `lib/main.dart` `bootstrap()`: `DeviceHints.read()`,
  settings, then `WambitoApp` (`lib/app.dart`). Router: `lib/router.dart` (go_router).
- One folder per feature (`lib/home/`, `lib/capture/`, `lib/budgets/`, …); Riverpod 3 providers
  sit next to their feature; tests override them.
- `lib/capture_auto/`: Settings → "Captura automática" (switch per source, notification-access
  state, restricted-settings steps). "¿Cómo funciona?" (`how_capture_works.dart`, demos in
  `capture_demos.dart`, twin of `apps/web/app/features/capture/`): five steps in an `LkSheet`
  `PageView`, shown on the first switch on (`askAccess: true`, ends with "Activar acceso", the
  prominent disclosure) and from the section's link (ends with "Entendido"); dots, Siguiente and
  the last step's disclosure and button sit in the sheet's stuck footer (that disclosure is the
  Play prominent disclosure). Scenes `assets/wambi/capture-step1..5.webp`, byte-identical to the
  web copies (`test/tooling/capture_scenes_test.dart`). Tests: `test/l10n/capture_copy_test.dart`
  (no language words; app copy equals web copy), parity pairs in
  `test/parity/capture_how_parity_test.dart`.
  `capture_platform.dart` wraps the `wambito/capture` channel (`autoCapturePlatformProvider`; no channel ⇒ `status()` null ⇒ the section
  hides); `SessionController.signOut`/`accountDeleted` call its `clearQueue()`, and every sign-in
  (`_signedIn`) and a start the server confirms call `sendQueued(userId)` (a 401 keeps the queue).
  Tests fake it with
  `test/capture_auto/fakes.dart`.
- API: `lib/api/client.dart` (Dio, `WambitoApi`); headers from `lib/api/device.dart`
  (`x-wambito-timezone`, `-locale`, `-client: android` on both phones, the API's word for the app); server defaults to `https://app.wambito.com`,
  override `--dart-define=WAMBITO_SERVER=…` (`lib/api/server_address.dart`) or in Settings.
- Storage: secure storage for session and settings; widget snapshot JSON under
  `wambito.widget.snapshot` in `HomeWidgetPreferences` (`lib/home/widget_snapshot.dart`).
- `lib/review/`: the inbox of transactions detected from notifications (`needsReview`). `reviewProvider`
  (`review_controller.dart`, read once, invalidated by home on refresh/resume) feeds home's
  "N gastos por revisar" row (`ReviewHomeRow`) and `/review` (`ReviewScreen`): Bien and Confirmar
  todos call `ReviewRepository.confirm` (POST /v1/transactions/review, all or nothing); Cambiar opens
  the add sheet's edit flow, whose save adds `needsReview: false` (`TransactionPatch.confirming`) so it
  confirms and teaches in one PATCH. Rows carry the mark "por revisar · de Revolut" (`reviewMarkOf`).
  Tests fake the server with `test/review/fakes.dart` (`pumpHome`/`pumpSettingsApp` override it).
- `lib/crypto/`: the Dart port of `packages/crypto`, one file per TS file (`crypto.dart` exports them), on
  `cryptography` (pure Dart in tests) and `cryptography_flutter` (native, registers itself). The device private
  key is raw 32 bytes. `test/crypto/vectors_test.dart` must pass `packages/crypto/test-vectors.json`
  byte for byte; a format change needs a new `enc_v` and vectors on both sides. `prfSalt` lives in `wraps.dart`.
- `lib/local/`: the phone's end-to-end encryption, each file the twin of one in `apps/web/app/local/`
  (`prf.dart` = `prf.ts`: the passkey PRF over the `wambito/passkeys` channel, on iOS 18+ and Android).
  `store.dart` + `memory_store.dart` (`FinanceStore`; the shared contract is `test/local/store_contract.dart`,
  run by every store), `db.dart` + `sqlite_store.dart` (`SqliteStore.open(userId)`: the vault, file
  `wambito-vault-<userId>.db` in the app support directory, one table per record type plus `outbox`,
  `meta`, `quarantine`; a local write updates record and outbox in one SQLite transaction, all
  operations go through one queue; keys are not in it, they live in secure storage; tests use
  `sqflite_common_ffi` in a temp dir via the `directory`/`factory` arguments).
  `lib/debug/prf_probe_screen.dart` is `/debug/prf`, registered only when `kDebugMode`.
- `lib/search/`: `/search` (`SearchScreen`, twin of `apps/web/app/features/search/`), opened by the
  magnifier in home's header (`home.search`). `searchControllerProvider` (`search_controller.dart`)
  holds the filters and results: text debounced 300 ms, kind, categories and status searched at once,
  only the latest request lands, `loadMore` waits for a pending debounce, `retry` repeats what failed
  (a page or the first page/refresh); text capped at 100 characters, categories at 20.
  `SearchRepository` (`search_repository.dart`) is `GET /v1/transactions` with `totals=true`; the
  totals line hides when the server sends none. The screen uses home's categories (archived too),
  loads the next page when the end is near, and after `openEditSheet` (replaceable in tests with
  `searchOpenEditProvider`) calls `refresh()`. Tests: `test/search/` (fake repository through the provider).
- Deep links `wambito://{add,capture,due,progress,home,review}` (`lib/launch/launch_links.dart`);
  `wambito://review` and `wambito://review/<id>` (one segment, `launchReviewIdOf`) push `/review` or
  `/review/<id>` over home, which opens that transaction in the editor.

## Android (`android/app/src/main/kotlin/com/wambito/app/`)

- `MainActivity.kt`: takes the launch link. Channels:
  `wambito/*`, registered in `MainActivity.kt`; names match the Dart constants (rename both at once).
- `widget/`: Glance widgets via home_widget; `notices/`: WorkManager `DueWorker`/`GuestWorker`,
  local notices only; `capture/`: the queue of captures parsed from bank notifications
  (`CaptureQueue`: each item tagged with the account id it was captured for, the prefs' `owner`
  then; `adopt(userId)` drops the items of another account or of none, old untagged items included;
  only the owner's items are sent, and only while the session mark matches `ownerMark`, which
  `sendQueued` stores), `CaptureApi` (`POST /v1/captures`, confirm) and WorkManager `SendCapturesWorker`
  (`CaptureHooks` replaces the session and the notifier in tests). The notification text is never
  queued, sent or logged. `CaptureListener` (a `NotificationListenerService`) reads only the packages
  enabled in `CaptureSettings` (prefs `wambito.capture.sources`), hands them to `BankParsers` (`RevolutParser`
  and `GoogleWalletParser`, expenses only in pt, it, en and es, one strict line per language and
  payment kind, sharing `Money` (comma or point decimal, any thousands separator); each line says
  where it comes from: seen on our phone (pt), another project's capture or tests (it, en) or nothing
  yet (es), so a new language needs a real sample; income returns null until samples exist; a parser
  that throws drops the notification) and queues
  the result; `CaptureChannel` is `wambito/capture`: `status`,
  `setSource`, `openAccessSettings`, `openAppInfo`, `clearQueue` (on sign-out: items and owner),
  `sendQueued` (`{userId}`, after a sign-in: `adopt` + send), `dismiss` (`{ids}`, confirmed in the
  app) and `keepOnly` (`{ids, before}`: `reviewProvider` sends every read under a full page; capture
  notifications of other ids posted before `before` go, so confirms on the web or by an assistant clear too). `CapturePoster` (the
  default `CaptureHooks.notifier`) posts the silent notification per detected transaction (title "Wambi", small icon
  `ic_notice` = Wambi's face cut from `ic_launcher_monochrome.xml`) on channel
  `wambito.capture` (LOW; id = `notificationId(transactionId)`, so a merged answer updates it, and one
  already confirmed (`needsReview` false) is `dismiss`ed instead; a group
  summary from 2): "Bien" is an immutable broadcast to the non-exported `ConfirmReceiver` →
  `CaptureScheduler.enqueueConfirm` → `ConfirmCaptureWorker` (one unique job per transaction,
  `wambito.capture.confirm.<id>`, KEEP; POST review, then cancels the notification; a 4xx other than
  401/408/429, 404 included, drops it; at most `MAX_ATTEMPTS` = 8 runs, then the notification stays
  for another tap), "Cambiar" opens `wambito://review/<id>` through the launch alias. Words in
  `CaptureText` (strings `capture_*`, language from `NoticeSettings`). Voice: Vosk, never Android's SpeechRecognizer
  (`voice/VoiceChannel.kt`, `wambito/voice` + `wambito/voice/events`; models kept per process by
  `ModelCache`: `VoiceModels` for Vosk, `PreciseModels` for the precise model keyed `path#language`: Canary for es/en, Parakeet for it/pt,
  told apart by its `joiner.int8.onnx` (`kindOf`)). With
  `precisePath`/`language` in the listen args the recording is kept in memory (`PcmBuffer`, 30 s max,
  never on disk, sent or logged) and `Refine` re-transcribes it on release (waits ≤ 3 s for a loading
  model): events `refining`, then `refined {text}` or `refine_failed {code: timeout|failed}`, between
  Vosk's `result`s and `done`; methods `deviceQualifies({minRamBytes?})` (Parakeet asks 5 GiB, else 3), `warmUp`/`isWarm` with `precisePath`/
  `language`, `releaseModels` frees both. `CanaryRecognizer` and `ParakeetRecognizer` are in `src/precise` only. Passkeys: androidx.credentials.

## iOS (`ios/`)

- `ios/Runner/`: one Swift folder per channel, all registered in `AppDelegate.swift`
  `registerChannels(messenger:)` (called from `didInitializeImplicitFlutterEngine`); names match the
  Dart constants, as on Android. The app uses a UIScene `SceneDelegate` (a `FlutterSceneDelegate`),
  so a link arriving on a scene reaches Dart through `LaunchSceneHandler` (in `Launch/`), not
  through `AppDelegate`.
  - `Device/`: `wambito/device` (`timeZone`, `openUrl`, `appVersion`); `Haptics/`: `wambito/haptics` (`vibrate`);
    `Sounds/`: `wambito/sounds` (`preload`, `play`); `Launch/`: `wambito/launch` (`take`, the
    `wambito://` links and the Universal Links of `app.wambito.com`); `Files/`: `wambito/files`
    (`pick`, `save`, `share`, `clearShared`: CSV import and export, share sheet);
    `Passkeys/`: `wambito/passkeys` (`isSupported`, `get`, `getAvailable`, `create`:
    AuthenticationServices); `Notices/`: `wambito/notices` (`scheduleDue`, `cancelDue`,
    `scheduleGuest`, `cancelGuest`, `permission`, `requestPermission`), local notices only
    (`UNUserNotificationCenter`; `KeychainSession` reads the session `flutter_secure_storage` keeps).
  - Words of the notices: `{es,en,it,pt}.lproj/Notices.strings`, generated from the Android
    `strings.xml` by `dart run scripts/gen-ios-strings.dart` (CI fails when stale), so both phones say
    the same words. `InfoPlist.strings` are the permission texts. `PrivacyInfo.xcprivacy` and
    `Runner.entitlements` (Associated Domains for passkeys and links) live beside them.
  - Adding a channel: a Swift file per area under `ios/Runner/`, one `private var` and one line in
    `registerChannels`. The Runner target is not a synchronized folder group: add every new file by
    hand to `ios/Runner.xcodeproj/project.pbxproj` (file reference, group per area, build file, the
    Sources or Resources phase), IDs unique (grep first).
- `ios/WambitoNative/`: Swift package with the logic that needs no UIKit (`NoticeTimes`, `DueToday`,
  `LaunchLinks`, `ExternalLinks`, `FileTransfer`, `HapticSpec`, `WebAuthnJSON`); the Runner imports
  it. Put new pure logic here with a test in `Tests/WambitoNativeTests/` (`swift test`); a channel
  file stays a thin wrapper. Dart twins (`launch_links.dart`, notice times) are pinned by the same
  cases.
- Signing: the team id lives only in `ios/Flutter/Signing.xcconfig` (git-ignored; copy
  `Signing.xcconfig.example`), never in the pbxproj: `scripts/check-ios-signing.sh` (tested by
  `scripts/test-check-ios-signing.sh`) fails on a team id there or a tracked `Signing.xcconfig`.
  `ios/ExportOptions.plist` is for the release; `.github/workflows/ios-release.yml` builds on a
  `mobile-v*` tag and uploads to App Store Connect (`docs/mobile/ios.md`).
- Native channels on both phones: `scripts/check-channels.sh` (repo root; CI `check`) fails when a
  channel or method Dart calls is missing from the Kotlin or the Swift side; what one phone cannot
  have is listed with a reason in `.github/channel-allowlist.txt` (`ios-impossible`, `ios-part-two`,
  `android-only`).
- iOS lacks, by design: automatic capture (`wambito/capture`, no API for it), widgets (the setting
  is hidden on iOS), and voice until part two (`wambito/voice*`). Dart hides them when the channel
  or platform is absent.
- `ios/**` is in `analysis_options.yaml`'s excludes (Flutter writes it on every `pub get` once `ios/`
  exists; keep it committed). Do not run `flutter create` again.

## Generated

- See root `AGENTS.md` (`lib/api/gen`, `tokens.g.dart`, l10n). `scripts/gen-api.sh` needs root
  `pnpm install`, JDK 17, Flutter. ARBs `lib/l10n/app_{es,en,it,pt}.arb`, es is the template.

## Commands (from `apps/mobile`, `export PATH="$HOME/development/flutter/bin:$PATH"`)

- `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test --exclude-tags golden` (CI).
- Goldens: `flutter test --tags golden` (`--update-goldens`); on macOS without PingFang set
  `PARITY_PINGFANG` to a `PingFang.ttc` (see `test/support/parity.dart`). CI skips goldens.
- Parity (`docs/mobile/parity.md`, list `test/parity/parity.json`): `pnpm --filter @wambito/web
  parity:fixtures|parity:shots [id]`, `flutter test --update-goldens test/parity`,
  `dart run tool/parity/compose.dart --max 2 [id]`.
- Kotlin: `cd android && JAVA_HOME=<JDK 17> ./gradlew :app:testDebugUnitTest --console=plain`.
- iOS (macOS, Xcode): `swift test --package-path ios/WambitoNative`; unsigned build `flutter build ios
  --release --no-codesign`; `scripts/check-ios-signing.sh`, `scripts/test-check-ios-signing.sh`;
  `dart run scripts/gen-ios-strings.dart` after changing a notice string; `../../scripts/check-channels.sh`.
  CI's `ios` job runs the signing guard, `swift test` and the unsigned build. On a device: set
  `Signing.xcconfig`, then `xcodebuild … -destination id=<device> -allowProvisioningUpdates build`.
- Integration tests (emulator + root dev stack): `scripts/run-integration-tests.sh`.
- Store listing images (emulator + root dev stack; `docs/mobile/play.md`): `tool/store_shots/run.sh`, then
  `node tool/store_shots/compose.cjs`.
- F-Droid (`docs/mobile/fdroid.md` explains the whole build):
  - `scripts/build-native-deps.sh --vosk-src <dir> --jna-src <dir> --ndk <NDK 28.2.13676358>
    [--abi <one ABI>] [--work <dir>]` builds Vosk and JNA from source (Linux x86_64 only, a
    linux/amd64 container on a Mac; 46 min with `--jobs 4`, about half with `--abi`) into
    `android/third_party/m2` (git-ignored). `scripts/test-build-native-deps-args.sh` (CI) tests
    its arguments.
  - The switch `-Pwambito.nativeFromSource=true` (`flutter build apk -P ...`, or, for `gradlew` and the check scripts,
    `env 'ORG_GRADLE_PROJECT_wambito.nativeFromSource=true' scripts/check-no-google.sh`; the name has
    a dot, so `export` and a bare `NAME=value` prefix do not work) takes
    those artifacts. ARM only, so off for the x86_64 emulator. `scripts/test-native-switch.sh`
    (CI) tests it.
  - The precise model on F-Droid (arm64-v8a only): `scripts/build-sherpa-onnx.sh --ndk <NDK 28.2.13676358>
    [--srclibs <dir>] [--work <dir>]` builds onnxruntime 1.28.2 and sherpa-onnx 2.0.1's JNI library
    from 24 pinned git checkouts (no network; about 80 min emulated) into
    `android/third_party/sherpa-onnx-src` (`jniLibs/`, the AAR's Kotlin API in `kotlin/`, `SOURCES`).
    `-Pwambito.preciseFromSource=true` (only with `wambito.nativeFromSource`) compiles and packs them
    with `src/precise` instead of `src/noPrecise`; no artifact, so the lockfiles do not change.
    `scripts/test-build-sherpa-onnx-args.sh` (CI) tests its arguments and pins; `test-native-switch.sh`
    the switch.
  - `scripts/package-canary.sh [--model canary|parakeet] [--check]` builds a precise model's zip for the voice-models-v2 release from sherpa-onnx's archive (not committed; prints its size and SHA-256; publish the zip from one run and pin that hash, `--check` proves reproducibility on one machine).
  - sherpa-onnx 2.0.1 (the precise voice model's runtime) for the Play and GitHub builds:
    `scripts/fetch-sherpa-onnx.sh` downloads its AAR, checks the pinned SHA-256 and installs it in
    `android/third_party/m2`; run it before any Gradle or `flutter build` (CI and `release.sh` do).
    `scripts/test-fetch-sherpa-onnx.sh` (CI) tests it offline. Code that uses `com.k2fsa.sherpa.onnx`
    goes in `android/app/src/precise/kotlin`, never in `src/main`: the F-Droid armeabi-v7a build swaps
    that folder for `src/noPrecise/kotlin` (stand-ins), and both define `voice.PreciseRuntime.linked`. Adds ~31 MB
    to the arm64 APK. `docs/mobile/setup.md` has the details.
  - Recipe: `fdroid/com.wambito.app.yml` is the source of truth, copied to fdroiddata when
    submitting; one build per ABI, srclibs in `fdroid/srclibs/*.yml`, natives built in `build:`
    (after F-Droid's source scan). Change it together with the revisions in `build-native-deps.sh`
    and `build-sherpa-onnx.sh` (`scripts/check-fdroid-recipe.sh`, CI, fails on drift from them and
    `.flutter-version`; the arm64-v8a entry lists the 24 sherpa-onnx sources, three of them
    fdroiddata's own srclibs). After
    submission fdroiddata's copy is the live one: such changes need their own fdroiddata merge
    request before tagging (`docs/mobile/fdroid.md`).
    `UpdateCheckData` reads `pubspec.yaml`'s version at a `mobile-v*` tag (`docs/mobile/release.md`).
    The text for the merge request is `fdroid/MERGE_REQUEST.md`.
  - `scripts/fdroid-build-local.sh <commit> [--version X.Y.Z] [--abi <one ABI>]` runs `fdroid
    lint`, `fdroid build` and `fdroid scanner` in F-Droid's buildserver image against a scratch
    copy of that commit (Docker, about an hour per ABI on 4 emulated cores; nothing is pushed).
  - Gradle locks: `android/app/gradle.lockfile`, and `gradle-fdroid.lockfile` for the switch.
    After changing a dependency, rewrite the first with `./gradlew :app:dependencies --write-locks`
    and the second with the `sed` in `docs/mobile/setup.md` ("Dependency locks"; no native build; it also drops
    the sherpa-onnx line),
    and commit both. `scripts/check-gradle-locks.sh` (CI) checks the first; `scripts/check-fdroid-lock.sh`
    (CI, text only) checks that the second is the first with the two `-src` substitutions and no sherpa-onnx line.
  - The Gradle wrapper jar is committed: the official one for the version in
    `gradle-wrapper.properties`.
- Release self-tests: `scripts/test-release.sh`, `scripts/check-fastlane.sh` (the five listings: texts,
  changelog ≤500 bytes with the same version codes in all, screenshots and feature graphic), `scripts/check-permissions.sh`.
- Google Play: `scripts/release.sh --play` also builds `wambito-<version>.aab` (versionCode base × 10 + 0),
  signed with `jarsigner` by the upload key (`WAMBITO_UPLOAD_KEYSTORE`, `_KEY_ALIAS`, `_KEYSTORE_PASSWORD`,
  `_KEY_PASSWORD`), never the app key (refused); read back with `aapt2` (the base module
  as a proto APK, `release_aab_base_apk`). Play App Signing holds the app key (handed over once with PEPK), so the
  Play build shares the APK's signature. Console forms and steps: `docs/mobile/play.md`.

## Traps

- See root `AGENTS.md`: money slang, the signing key's alias, secrets (the keystore too). Here
  the slang lives in `lib/capture/parser/`, `lib/capture/engine/`, `lib/money/format.dart` and the ARBs.
- Persistent state on phones: prefs file names, WorkManager unique names (`wambito.widget.refresh`,
  `wambito.widget.midnight`, `wambito.notice.due`, `wambito.notice.guest`, `wambito.capture.send`,
  `wambito.capture.confirm.<id>`; the old shared `wambito.capture.confirm` chain is only cancelled,
  at every Bien; prefs `wambito.capture.queue`, `wambito.capture.sources`; channel
  `wambito.capture`; listener class `com.wambito.app.capture.CaptureListener`), widget receiver classes
  (renaming removes placed widgets), the snapshot key. Changing any needs a migration.
- No `gradlew` is tracked; Kotlin-only runs can skip the Flutter compile with `-x compileFlutterBuildDebug`.
- Never block on a WorkManager future (`.get()`) in code a Worker runs: deadlocks in tests.
- `test/tooling/*` reads Android files; `widget_android_test.dart` there pins Dart = Kotlin.
- `manifest_test` counts `android:host="due"` once (only `wambito://` links).
- About 55 goldens already fail on the founder's Mac: compare with the base first. Regenerated
  parity fixtures change millisecond timestamps: keep only the intended diff.
