# iOS voice: dictation on the iPhone with sherpa-onnx

Status: design, 2026-11-12. Second of two iOS parts; the first is
`2026-11-11-ios-base-design.md` (PR slinqer/wambito#62), and this branch starts from it.

## 1. Goal

The voice button works on iOS as on Android: the person holds it, sees the words appear while
talking, and gets a movement to review. iOS runs only sherpa-onnx, no Vosk:

- Spanish and English with NVIDIA Canary 180M Flash int8, Italian and Portuguese with Parakeet TDT
  0.6B v3 int8: the same models, release (`voice-models-v2`) and SHA-256 as Android's precise pass;
- live text for all four languages, by re-reading the recording while it runs;
- the models download the first time voice is used, as on Android; nothing of them ships in the
  app;
- iPhones with less than 3 GiB of RAM get no voice (the button is hidden, as on an Android phone
  without the models); Italian and Portuguese need 5 GiB (Parakeet), as on Android.

Out: Vosk on iOS, a model picker, on-device LLMs, changing anything Android does.

Success: on the iOS simulator on a Mac, with the Mac's microphone, "18 lukas almuerzo" spoken in
Spanish shows live text and ends as an $18.000 expense to review; the same in Portuguese with
Parakeet; then the same on the founder's iPhone.

## 2. Dart

- New `lib/capture/engine/precise_engine.dart`: `PreciseEngine implements SpeechEngine`, chosen by
  `speechEngineProvider` when `Platform.isIOS` (Android keeps `VoskEngine`, untouched). It reads
  the precise model's folder from `preciseModelStoreProvider`; no folder is
  `SpeechFailure(noModel)`, as in `VoskEngine`.
- It shares `VoskEngine`'s limits: `nothingHeardLimit` 8 s, `longestListen` 30 s, `refineLimit`
  3 s. The end-of-speech pause is 1.5 s after the last `partial` whose text changed and is not
  empty (there are no `result` events on iOS). Its output is the `refined` text, else the last
  partial.
- `VoicePlatform` gains three methods for an engine with no Vosk model, sent over the same
  `wambito/voice` methods with no `modelPath` or `grammar`:
  `warmUpPrecise({required String precisePath, required String language})`,
  `isWarmPrecise({...same})` and `startPrecise({...same}) → Stream<VoiceEvent>`. Android never
  receives them.
- Download: on iOS only the precise model is downloaded (the existing `ModelStore` and its UI,
  with `preciseModelStoreProvider`); the Vosk download and the "precise offer" are not shown. The
  free-space check and SHA-256 check are unchanged.
- Gate: on iOS voice is offered when `deviceQualifies` is true for the language's model
  (`minRamBytes` from `VoiceModel`, 3 GiB by default, Parakeet 5 GiB); otherwise the voice button
  is hidden.
- About's licence list (`lib/settings/licenses.dart`): on iOS it lists sherpa-onnx, onnxruntime and
  what they link (the same texts as Android) and Canary/Parakeet (CC BY 4.0), and not Vosk or JNA,
  which iOS does not ship.

## 3. Swift: the `wambito/voice` channel

Files in `ios/Runner/Voice/` (added to the Runner target in `project.pbxproj` by hand), logic that
needs no audio or model in `ios/WambitoNative` (tested with `swift test`). Registered in
`AppDelegate.registerChannels(messenger:)` like the other channels.

Methods, same names, arguments and error codes as `VoiceChannel.kt`:

| Method | iOS |
|---|---|
| `supported` | true (sherpa-onnx is linked statically) |
| `requestPermission` | `AVAudioSession.requestRecordPermission` (iOS 16; `AVAudioApplication` from 17); true when granted |
| `deviceQualifies({minRamBytes})` | `ProcessInfo.physicalMemory >= minRamBytes ?? 3 GiB` |
| `warmUp`, `isWarm` | with `precisePath` and `language` only (section 2) |
| `stop` | ends recording; the final pass follows, then `done` |
| `modelsDirectory` | Application Support/`voice-models`, created, excluded from iCloud backup |
| `freeBytes` | `volumeAvailableCapacityForImportantUsage` of that folder |
| `unzip({zip, into})` | `ZipExtract` (below), on a background queue |
| `releaseModels` | drops the loaded recognizer |

Events on `wambito/voice/events`, same maps as Android: `ready`, `level` (0..1 from the RMS in
dBFS, floor −50, 40 ms chunks), `partial`, `refining`, `refined`, `refine_failed` (`timeout` or
`failed`), `done`, `error` (`permission`, `mic_unavailable`, `bad_arguments`, `no_model`,
`failed`). No `result`.

Recording:

- `AVAudioSession` category `.record` (mode `.measurement`) while listening; back to `.ambient`
  and deactivated with `.notifyOthersOnDeactivation` when it ends, so other audio resumes.
- `AVAudioEngine`'s input tap converted with `AVAudioConverter` to 16 kHz mono Float32, sent on in
  40 ms chunks (640 samples) into `PcmBuffer` (30 s cap, as `PcmBuffer.kt`).
- An interruption (call, Siri) or a route change that loses the input ends the recording as
  `stop` would.

Recognition (one `SherpaOnnxOfflineRecognizer`, 2 threads, CPU provider):

- Canary or Parakeet is told apart as on Android: a folder with `joiner.int8.onnx` is Parakeet
  (NeMo transducer config), else Canary (`canary` config with the language as source and target).
- `ModelCache`: a Swift port of `ModelCache.kt` keyed by `path#language`; `warmUp` loads in the
  background, `isWarm` answers whether it is loaded and the microphone is granted; dropped on
  `releaseModels` and on a memory warning.
- Live: `LiveSchedule` (WambitoNative) decides when to decode: first at 1 s of audio, then every
  0.5 s, skipped while the previous decode still runs. Each decode reads the whole buffer so far;
  `LiveText` (WambitoNative) drops the last word unless the recording has ended, and a `partial`
  is sent only when the text changed.
- Final: on `stop` (or the 30 s cap), `refining`, then one decode of the whole buffer with a 3 s
  limit (`Refine.kt`'s): `refined` with its text, or `refine_failed` `timeout`/`failed`; then
  `done`. A decode still running when the limit passes is left to finish and its text dropped.

`ZipExtract` (WambitoNative): extracts the model zips with the Compression framework (stored and
deflate entries; anything else, encrypted or zip64 is an error), refuses entries outside `into`
(zip-slip) as `ZipExtract.kt` does, and writes in chunks so Parakeet's 670 MB never sits in memory.

The Swift API is k2-fsa's `swift-api-examples/SherpaOnnx.swift` at v2.0.1, copied as
`ios/Runner/Voice/SherpaOnnx.swift` with its Apache-2.0 header and the commit it came from; the
bridging header imports sherpa-onnx's `c-api.h`.

## 4. sherpa-onnx for iOS

k2-fsa publishes no iOS build of v2.0.1, so it is built once, as upstream builds it, and kept in
this repository's releases (the "prebuilt, whole" choice: no trimming of onnxruntime):

- `apps/mobile/scripts/build-sherpa-onnx-ios.sh` (macOS, Xcode, cmake): checks out sherpa-onnx at
  the v2.0.1 commit (`af2d8d81dbfa61c4cea4c568da78f3982edca005`, as `build-sherpa-onnx.sh`), takes
  `onnxruntime-ios-static-xcframework-1.28.2.xcframework.zip` from `csukuangfj/onnxruntime-libs`
  with a pinned SHA-256 and size (33821118 bytes), runs upstream's `build-ios.sh` unchanged, and
  zips `sherpa-onnx.xcframework`, `onnxruntime.xcframework` and a `SOURCES` file (each input and its
  revision or hash) as `sherpa-onnx-ios-2.0.1.zip`. Device slice arm64, simulator arm64 and
  x86_64; static libraries.
- The zip is uploaded by hand, once, to the release `ios-sherpa-onnx-2.0.1` of
  `slinqer/wambito`, after the founder approves.
- `apps/mobile/scripts/fetch-sherpa-onnx-ios.sh`, shaped like `fetch-sherpa-onnx.sh`: downloads
  that asset, checks SHA-256 and size before writing anything, installs into
  `apps/mobile/ios/third_party/sherpa-onnx/` (git-ignored); idempotent; `--from <file>`; exit codes
  0, 1 (mismatch), 2 (download or install failed); `SHERPA_ONNX_IOS_SHA256`/`_SIZE` overrides for
  its test only.
- The Runner target links both xcframeworks from that folder (`-lc++`). A build without them fails
  in a Run Script phase that names the fetch script.
- The App Store build carries the arm64 device slice only (app thinning). The runtime must ship in
  the app: App Review guideline 2.5.2 forbids downloading executable code, and iOS loads no
  library the app was not signed with. Only the models (data) download later.

## 5. CI

- `ios` job (`ci.yml`): `scripts/test-fetch-sherpa-onnx-ios.sh`, `scripts/fetch-sherpa-onnx-ios.sh`,
  then the existing `swift test` and `flutter build ios --release --no-codesign` (which proves the
  link).
- `ios-release.yml`: runs the fetch script before archiving.
- `.github/channel-allowlist.txt` loses `wambito/voice` and `wambito/voice/events`; the channel
  guard then passes because the Swift side exists. The reason `ios-part-two` stays defined only if
  another entry still uses it; otherwise it is removed with its line in the header.

## 6. Tests

- Dart (`flutter test`, fake channel): `PreciseEngine` stops 1.5 s after the last changed
  non-empty partial, not after an unchanged or empty one; ends with `refined`, else the last
  partial on `refine_failed`; maps each error code to its `SpeechFailure`; nothing heard in 8 s
  stops; 30 s stops. `speechEngineProvider` gives `PreciseEngine` on iOS and `VoskEngine` on
  Android. On iOS only the precise model is offered for download, and the voice button is hidden
  when `deviceQualifies` is false. iOS's licence list has sherpa-onnx and not Vosk.
- Swift (`swift test`, `WambitoNative`): `LiveSchedule` (first decode at 1 s, every 0.5 s, skip
  while busy, none after stop); `LiveText` (last word dropped while recording, kept at the end,
  one word stays empty); the level (silence 0, full scale 1, floor −50 dBFS); `PcmBuffer`'s 30 s
  cap; the 3 s final limit (`AnswerOnce`-style: the late answer is dropped); `deviceQualifies`'
  thresholds; `ZipExtract` (stored, deflate, zip-slip refused, zip64 refused, a truncated file
  fails without leaving files).
- Scripts: `test-fetch-sherpa-onnx-ios.sh` (wrong SHA-256 or size refused and nothing written; a
  matching install left alone), run in CI.
- Real model, local only: an XCTest in `RunnerTests` on the simulator transcribes a short Spanish
  WAV with Canary and a Portuguese one with Parakeet, made by `say` on the Mac and kept as
  invented fixtures. It runs only when `WAMBITO_VOICE_MODELS` points at the unzipped models and is
  skipped otherwise (the models are hundreds of MB; CI does not download them).
- By hand on the simulator, with the founder: download Canary in the app, dictate with the Mac's
  microphone, check live text, the pause, the final text and the amount; Portuguese with Parakeet.
- By hand on the iPhone, added to the hand-check list: the same, plus music in another app pausing
  while recording and resuming after, and a phone call during recording. The RAM rule (an iPhone 8,
  2 GiB, gets no voice) is covered by the unit test, not by hand.

## 7. Docs to update

- `apps/mobile/AGENTS.md`: the iOS voice files, the fetch script, `ios/third_party`.
- `docs/mobile/ios.md`: the fetch step for local builds; `docs/mobile/setup.md` if it lists the
  fetch scripts.
- Root `AGENTS.md`'s CI list (`ios` job's new steps).
- `.gitignore`: `apps/mobile/ios/third_party/`.

No API or MCP change, so no `CHANGELOG.md` line.
