# Canary Live Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On phones that have Canary for es/en, show Canary's text live while the person talks, end the listen with a VAD instead of Vosk, and download Canary alone.

**Architecture:** A plain Kotlin class, `LiveTranscript`, decides when to re-decode the open VAD segment and what text to show; sherpa-onnx's Silero VAD and Canary sit behind interfaces in `src/precise`. The voice channel gains a `live` listen mode with `live` and `speech_end` events and no Vosk model. On the Dart side the engine picks live mode per listen, and the capture session offers Canary alone on those phones, falling back to the current Vosk flow if the person declined Canary or it failed.

**Tech Stack:** Kotlin (Android, JUnit/Robolectric unit tests), sherpa-onnx 2.0.1 AAR (`Vad`, `SileroVadModelConfig`, `OfflineRecognizer`), Flutter/Dart (Riverpod 3), Bash (fetch script).

**Spec:** `docs/superpowers/specs/2026-11-06-voice-canary-live-design.md`. Prototype for reference only (not to merge): local branch `spike/canary-live`, commit 60b548c.

## Global Constraints

- Live mode only for `es`/`en` with Canary installed, on a Play/GitHub build; Parakeet languages (`it`/`pt`), non-qualifying phones and the F-Droid build (`-Pwambito.nativeFromSource=true`) behave exactly as on `main`.
- First live pass after 1 s of speech in the open segment (`LIVE_START_MS = 1000`); then one pass at a time, the next starting `max(500 ms, 2 × last pass duration)` after the last one started (`LIVE_STEP_MS = 500`).
- While talking, the open segment is shown without its last word; on release, the final pass shows it whole.
- VAD: Silero `silero_vad.onnx`, 643854 bytes, SHA-256 `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6`, from `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`, MIT. Fetched by `scripts/fetch-sherpa-onnx.sh`, never committed, packaged as an asset only without the switch.
- A segment closes at the VAD's end of speech or at 10 s (`maxSpeechDuration = 10`); `speech_end` fires after 1.5 s of silence following speech (the current `endOfSpeechPause`).
- "Refinando…" shows only when the final pass has not answered within 300 ms of release; the whole final pass is still bounded by `refineLimit` (3 s), after which the last live text stands.
- Audio stays in memory only (`PcmBuffer`, 30 s cap); never on disk, sent or logged.
- Code using `com.k2fsa.sherpa.onnx` lives in `android/app/src/precise/kotlin`; `src/noPrecise/kotlin` has stand-ins.
- Copy: es is the ARB template; all four ARBs get every new key. Failing test first. Everything in the repo in English. Commits `feat(mobile): …`, staged by path, no `Co-Authored-By`.
- Whoever changes structure or commands updates `apps/mobile/AGENTS.md`.

## Review Focus

1. The person taps 🎤 and talks before Canary has loaded: nothing is lost; live text starts once it is loaded, and the final pass covers everything kept.
2. A phrase under 1 s ("pan"): no live pass ever runs; release still gives the final pass's text.
3. Talking past 10 s without a pause: the segment is closed and frozen, passes stay one phrase long.
4. Cancel (sheet closed, app backgrounded) during a live pass: no event after cancel, the pass ends before the recognizer is released or refined.
5. Canary fails to open or a pass throws in live mode: the listen ends with `precise_failed`, the session offers the basic model, and the next listen uses Vosk.

---

### Task 1: Fetch the Silero VAD next to the AAR

**Files:**
- Modify: `apps/mobile/scripts/fetch-sherpa-onnx.sh`
- Modify: `apps/mobile/scripts/test-fetch-sherpa-onnx.sh`
- Modify: `apps/mobile/android/app/build.gradle.kts` (assets source set)
- Modify: `apps/mobile/AGENTS.md`, `docs/mobile/setup.md`

**Interfaces:**
- Produces: the asset `voice/silero_vad.onnx` in the APK (Play/GitHub builds only), read by `AssetManager` path `voice/silero_vad.onnx`.

- [ ] **Step 1: Failing test.** In `test-fetch-sherpa-onnx.sh`, add cases with a new `--vad-from <file>` and `--assets <dir>` (the tests' offline inputs): a file of the pinned size and SHA-256 (override with `SILERO_VAD_SIZE`/`SILERO_VAD_SHA256` env as the AAR case does) lands at `<assets>/voice/silero_vad.onnx`; a mismatching one exits 1 and leaves no file; a second run with the file present downloads nothing.
- [ ] **Step 2:** Run `apps/mobile/scripts/test-fetch-sherpa-onnx.sh`; expect the new cases to FAIL.
- [ ] **Step 3: Implement** in `fetch-sherpa-onnx.sh`: default `ASSETS="$MOBILE/android/third_party/assets"`; download URL, size and SHA-256 from Global Constraints; atomic write (temp file + `mv`), as for the AAR.
- [ ] **Step 4:** Gradle: without the switch, `android.sourceSets.getByName("main").assets.srcDir("../third_party/assets")`; with it, nothing. Check: `flutter build apk --debug` then `unzip -l` lists `assets/voice/silero_vad.onnx`; `scripts/test-native-switch.sh` still passes.
- [ ] **Step 5:** Run the test script; expect PASS. Update `AGENTS.md` (the fetch line) and `docs/mobile/setup.md`.
- [ ] **Step 6: Commit** `feat(mobile): fetch the silero vad for live voice`.

### Task 2: `LiveTranscript`, the live decision logic

**Files:**
- Create: `apps/mobile/android/app/src/main/kotlin/com/wambito/app/voice/LiveTranscript.kt`
- Test: `apps/mobile/android/app/src/test/kotlin/com/wambito/app/voice/LiveTranscriptTest.kt`

**Interfaces:**
- Consumes: `PreciseRecognizer` (`transcribe(FloatArray, Int): String`), `PcmBuffer.SAMPLE_RATE`.
- Produces:
  - `interface SpeechGate : AutoCloseable { fun accept(samples: FloatArray): List<GateEvent> }` with `sealed class GateEvent { object SpeechStart; data class SegmentEnd(val samples: FloatArray); object Silence }` (`Silence` = 1.5 s quiet after speech).
  - `class LiveTranscript(recognizer: () -> PreciseRecognizer?, gate: SpeechGate, run: (Runnable) -> Unit, clock: () -> Long, show: (String) -> Unit, speechEnd: () -> Unit)` with `fun accept(samples: ShortArray, count: Int)`, `fun finish(): String` (waits for a pass in flight, decodes the open segment whole, returns closed segments + it) and `fun cancel()`.
  - Constants `LIVE_START_MS = 1000`, `LIVE_STEP_MS = 500`.

- [ ] **Step 1: Failing tests** (fake recognizer returning scripted text and recording calls; fake gate scripted per chunk; `run` executes on a captured queue; fake clock):
  - `no pass before 1 s of speech in the open segment`
  - `a pass every 500 ms, never two at once` (queue holds one job; while it is pending no new one is submitted)
  - `a slow pass spaces the next by twice its duration` (pass of 400 ms → next ≥ 800 ms after it started)
  - `the open segment is shown without its last word; closed segments whole` (`"pan y leche"` open → shows `"pan y"`; after `SegmentEnd` with text `"pan y leche."` → shows `"pan y leche."`)
  - `finish decodes the open segment whole and joins the closed ones`
  - `a phrase under 1 s gets no live pass but finish returns its text`
  - `Silence calls speechEnd once`
  - `nothing is shown when the recognizer is not loaded yet; audio is kept for finish` (`recognizer()` null until later)
  - `cancel stops showing and finish after cancel returns ""`
- [ ] **Step 2:** `cd apps/mobile/android && JAVA_HOME=<JDK 17> ./gradlew :app:testDebugUnitTest --tests '*LiveTranscriptTest' -x compileFlutterBuildDebug --console=plain`; expect FAIL (unresolved).
- [ ] **Step 3: Implement.** Keep the open segment's samples (≤ 10 s, the gate closes it); a `show` text = closed texts + open text without last word, sent only when it changed. Not thread-safe by itself: `accept` and `finish` are called from the recording thread; `run` is the single live thread.
- [ ] **Step 4:** Run; expect PASS.
- [ ] **Step 5: Commit** `feat(mobile): live transcript logic for canary while talking`.

### Task 3: Silero gate in `src/precise`

**Files:**
- Create: `apps/mobile/android/app/src/precise/kotlin/com/wambito/app/voice/SileroGate.kt`
- Modify: `.../src/precise/kotlin/com/wambito/app/voice/PreciseRuntime.kt`, `.../src/noPrecise/kotlin/com/wambito/app/voice/PreciseRuntime.kt`

**Interfaces:**
- Consumes: `SpeechGate`, `GateEvent` (Task 2); asset `voice/silero_vad.onnx` (Task 1).
- Produces: `PreciseRuntime.openGate(assets: AssetManager): SpeechGate` (noPrecise: throws `UnsupportedOperationException`).

- [ ] **Step 1:** `SileroGate` wraps `Vad(assets, VadModelConfig(sileroVadModelConfig = SileroVadModelConfig(model = "voice/silero_vad.onnx", threshold = 0.5f, minSilenceDuration = 0.25f, minSpeechDuration = 0.25f, windowSize = 512, maxSpeechDuration = 10f), sampleRate = 16000, numThreads = 1))`. It buffers input into 512-sample windows; `isSpeechDetected()` rising → `SpeechStart`; each popped segment → `SegmentEnd(samples)`; 1.5 s of windows without speech after any speech → `Silence` once.
- [ ] **Step 2:** No JVM unit test (needs the native library); the logic it feeds is Task 2's. Compile both flavours: `./gradlew :app:compileDebugKotlin -x compileFlutterBuildDebug` and `scripts/test-native-switch.sh`.
- [ ] **Step 3: Commit** `feat(mobile): silero vad gate for live voice`.

### Task 4: Live mode in the voice channel

**Files:**
- Modify: `apps/mobile/android/app/src/main/kotlin/com/wambito/app/voice/VoiceChannel.kt`
- Test: `apps/mobile/android/app/src/test/kotlin/com/wambito/app/voice/` (existing patterns: `RefineTest`, `ModelCacheTest`)

**Interfaces:**
- Consumes: `LiveTranscript` (Task 2), `PreciseRuntime.openGate` (Task 3), `PreciseModels.cache`.
- Produces (channel contract, documented in the file's header):
  - listen args `{precisePath, language, live: true, grammar?}`; `modelPath` optional when `live` is true.
  - events: `ready`, `level`, `live {text}`, `speech_end`, then on release `refining`, `refined {text}` or `refine_failed {code}`, `done`; `error {code: precise_failed}` when Canary or the gate cannot open or a pass throws.
  - `warmUp`/`isWarm` accept `{precisePath, language, live: true}` without `modelPath` (they warm/check only the precise model).

- [ ] **Step 1: Failing tests** for what is testable without native code, by extracting the live record loop's decisions into a function taking a `SpeechGate` and recognizer opener (as `Refine` takes a `ModelCache`): `live listen sends live texts then refined then done`, `an opener that throws ends with error precise_failed`, `cancel during a pass sends nothing more`.
- [ ] **Step 2:** Run; expect FAIL.
- [ ] **Step 3: Implement** a `recordLive(...)` path beside `record(...)`: microphone first (as now), audio kept in `PcmBuffer` and fed to `LiveTranscript`; the precise model acquired from `PreciseModels.cache` (loading in the background; `LiveTranscript` waits for it, Review Focus 1); on stop, `refining` then `finish()` bounded as `Refine` is (3 s), `refined`, `done`. One live executor per `VoiceChannel`, shut down in `dispose()`.
- [ ] **Step 4:** Run all Kotlin unit tests; expect PASS.
- [ ] **Step 5: Commit** `feat(mobile): live canary listen mode in the voice channel`.

### Task 5: Dart engine: live mode per listen

**Files:**
- Modify: `apps/mobile/lib/capture/engine/voice_channel.dart` (events `VoiceLive(text)`, `VoiceSpeechEnd()`; `start`, `warmUp`, `isWarm` take `String? modelPath` and `bool live = false`)
- Modify: `apps/mobile/lib/capture/engine/vosk_engine.dart`
- Test: `apps/mobile/test/capture/vosk_engine_test.dart`, `test/capture/fakes` as used there

**Interfaces:**
- Consumes: channel contract (Task 4); `preciseModelStoreProvider`; `PreciseOffer` (`lib/capture/precise_offer.dart`).
- Produces: `const liveLocales = {'es', 'en'}`; `VoskEngine` chooses live when `liveLocales.contains(locale)`, the precise model is installed and its new constructor argument `Future<bool> Function() liveBlocked` (default `() async => false`; Task 6 wires it to `PreciseOffer.liveBlocked`) answers false. In live mode it needs no Vosk model, and `noModel` is thrown only when neither model is installed.

- [ ] **Step 1: Failing tests:** `live: shows live texts as they come`; `live: stops on speech_end`; `live: refining is reported only after 300 ms`; `live: a refine timeout keeps the last live text`; `live: precise_failed fails the listen with SpeechFailureKind.failed and detail precise_failed`; `it/pt never use live`; `es without the precise model uses Vosk as today`; `es with only Canary installed listens (no noModel)`.
- [ ] **Step 2:** `flutter test test/capture/vosk_engine_test.dart`; expect FAIL.
- [ ] **Step 3: Implement.** Reuse `_Session` timers (`nothingHeardLimit`, `longestListen`); in live mode `speech_end` triggers `stop()`.
- [ ] **Step 4:** Run; expect PASS. `flutter analyze` clean.
- [ ] **Step 5: Commit** `feat(mobile): the engine listens with live canary on es/en`.

### Task 6: Download and fallback in the capture session

**Files:**
- Modify: `apps/mobile/lib/capture/capture_session.dart`, `apps/mobile/lib/capture/capture_download.dart`, `apps/mobile/lib/capture/precise_offer.dart`, `apps/mobile/lib/capture/prewarm.dart`
- Modify: `apps/mobile/lib/l10n/app_{es,en,it,pt}.arb`
- Test: `apps/mobile/test/capture/capture_sheet_test.dart`, `test/capture/precise_offer_test.dart`

**Interfaces:**
- Consumes: Task 5's engine choice; `preciseEligibleProvider`; `PreciseOffer.shouldOffer/answer`.
- Produces:
  - `PreciseOffer.liveBlocked()` / `blockLive()`: a flag under the existing prefs (`wambito.voice.preciseOffer` store), set after a `precise_failed` listen; passed to `VoskEngine(liveBlocked:)` in `speechEngineProvider`.
  - Session: on an eligible es/en phone where the person has not declined Canary and live is not blocked, the offer downloads Canary alone, showing its size; `hasVoice` is true when either model is installed.
  - ARB key `captureUseBasicModel`: es "Usar el modelo básico", en "Use the basic model", it "Usa il modello base", pt "Usar o modelo básico"; and `captureLiveFailed`: es "La voz precisa falló en este teléfono.", en "The precise voice failed on this phone.", it "La voce precisa non ha funzionato su questo telefono.", pt "A voz precisa falhou neste telemóvel.".

- [ ] **Step 1: Failing tests:** `eligible es: the offer shows Canary's size alone and downloads only Canary`; `eligible es, Canary declined: the offer is Vosk alone (today's flow)`; `it on a 6 GB phone: the joint Vosk + Parakeet offer as today`; `precise_failed: a toast with Usar el modelo básico; tapping it downloads Vosk and the next listen uses Vosk`; `prewarm warms the precise model alone in live mode`.
- [ ] **Step 2:** Run; expect FAIL.
- [ ] **Step 3: Implement.** Keep the joint flow untouched for non-live locales.
- [ ] **Step 4:** Run the whole suite: `flutter test --exclude-tags golden`; expect PASS. Goldens touched by new copy: regenerate only the intended ones (`flutter test --tags golden --update-goldens test/capture`), compare with the base (about 55 already fail on the founder's Mac).
- [ ] **Step 5: Commit** `feat(mobile): canary alone for live voice, with a basic-model fallback`.

### Task 7: Licence and docs

**Files:**
- Modify: `apps/mobile/lib/settings/licenses.dart`, `apps/mobile/assets/licenses/` (add `silero-vad-mit.txt`), `pubspec.yaml` assets if listed per file, the four ARBs (`licenseNoticeSileroVad`), `test/settings/licenses_test.dart`
- Modify: `apps/mobile/AGENTS.md` (voice paragraph: live mode, events, `LiveTranscript`, `SileroGate`), `docs/mobile/fdroid.md` ("Open": no live mode on F-Droid)

- [ ] **Step 1: Failing test:** `Silero VAD is credited under MIT` (entry `Silero VAD, snakers4`, only when sherpa-onnx is in the build, as Canary's); add it to `the list never silently shrinks`.
- [ ] **Step 2:** Run; expect FAIL. **Step 3:** Implement (MIT text from the Silero VAD repository's LICENSE, copyright line as there). **Step 4:** PASS. **Step 5: Commit** `feat(mobile): credit silero vad`.

### Task 8: Trial build on the founder's phone

- [ ] **Step 1:** `flutter analyze`, `flutter test --exclude-tags golden`, Kotlin unit tests, `scripts/test-fetch-sherpa-onnx.sh`, `scripts/test-native-switch.sh`: all pass.
- [ ] **Step 2:** Build an unsigned arm64 release with `--build-number` above the phone's current one (installed: 100022 → use base 10003), have the founder sign it in a terminal tab (the keystore password is theirs), install with `adb install -r`.
- [ ] **Step 3:** The founder tries: short phrase, long phrase over 10 s, talking right after the tap, airplane mode. Record the outcome in the spec's "Open" section only if it changes a decision.
