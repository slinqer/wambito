# apps/mobile: the Android app (Flutter, Dart package `wambito`)

Android only, `com.wambito.app`. No Play Services or Firebase (`scripts/check-no-google.sh`);
deps pinned, free-licensed (`scripts/check-licenses.sh`). Setup, emulator, JDK 17:
`docs/mobile/setup.md`. Release and signing: `docs/mobile/release.md`.

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
  (`x-wambito-timezone`, `-locale`, `-client: android`); server defaults to `https://app.wambito.com`,
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
  and `GoogleWalletParser`, European Portuguese expenses only, sharing `PtAmount`; Revolut reads the
  card line «Gastou 12,50 €» and the Revolut Pay line «pagou €9.28 em …», decimal point allowed there only; income and the other
  languages return null until samples exist; a parser that throws drops the notification) and queues
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
- Integration tests (emulator + root dev stack): `scripts/run-integration-tests.sh`.
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
  - `scripts/package-canary.sh [--model canary|parakeet] [--check]` builds a precise model's zip for the voice-models-v2 release from sherpa-onnx's archive (not committed; prints its size and SHA-256; publish the zip from one run and pin that hash, `--check` proves reproducibility on one machine).
  - sherpa-onnx 2.0.1 (the precise voice model's runtime; Play and GitHub builds only):
    `scripts/fetch-sherpa-onnx.sh` downloads its AAR, checks the pinned SHA-256 and installs it in
    `android/third_party/m2`; run it before any Gradle or `flutter build` (CI and `release.sh` do).
    `scripts/test-fetch-sherpa-onnx.sh` (CI) tests it offline. Code that uses `com.k2fsa.sherpa.onnx`
    goes in `android/app/src/precise/kotlin`, never in `src/main`: the switch swaps that folder for
    `src/noPrecise/kotlin` (stand-ins), and both define `voice.PreciseRuntime.linked`. Adds ~31 MB
    to the arm64 APK. `docs/mobile/setup.md` has the details.
  - Recipe: `fdroid/com.wambito.app.yml` is the source of truth, copied to fdroiddata when
    submitting; one build per ABI, srclibs in `fdroid/srclibs/*.yml`, natives built in `build:`
    (after F-Droid's source scan). Change it together with the revisions in `build-native-deps.sh`
    (`scripts/check-fdroid-recipe.sh`, CI, fails on drift from them and `.flutter-version`). After
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
- Release self-tests: `scripts/test-release.sh`, `scripts/check-fastlane.sh` (changelog ≤500 bytes,
  same version codes in all four locales), `scripts/check-permissions.sh`.

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
