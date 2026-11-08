# fdroiddata merge request: com.wambito.app

Title: `New app: Wambito (com.wambito.app)`

Text for the merge request description. The recipe is `apps/mobile/fdroid/com.wambito.app.yml`; the
source libraries it needs are `apps/mobile/fdroid/srclibs/*.yml`, plus fdroiddata's own
`onnxruntime`, `abseil-cpp` and `cpuinfo`, reused as they are. Copy the recipe to
`metadata/com.wambito.app.yml` and the srclibs to `srclibs/`.

---

## The app

Wambito is a free personal finance app: log an expense in seconds (number pad, or one sentence typed
or dictated), see this month and your entries by day. Spanish, English, Italian and Portuguese.
Source: https://github.com/slinqer/wambito (monorepo; the app is in `apps/mobile`, Flutter and
Kotlin). License: AGPL-3.0-only. The metadata (descriptions, screenshots, changelogs) is in
`apps/mobile/fastlane/metadata/android`.

No ads, no analytics, no crash reporting, no Google Play Services or Firebase. CI fails if any
proprietary artifact appears in the resolved classpath (`apps/mobile/scripts/check-no-google.sh`)
and checks the permissions against an allowlist.

## How it is built

- One build entry per ABI (`armeabi-v7a` 100001, `arm64-v8a` 100002 for 1.0.0), `subdir:
  apps/mobile`, Flutter 3.47.7 from the `flutter` srclib, NDK r28c. `versionCode` is
  `(X*10000 + Y*100 + Z) * 10 + ABI digit`; `UpdateCheckMode: Tags ^mobile-v`, and the tagged
  commit carries the version in `pubspec.yaml` (read by `UpdateCheckData`).
- The only prebuilt native code the app used was Vosk (`libvosk.so`) and JNA (`libjnidispatch.so`)
  from Maven Central. The recipe builds both from source in `build:`, with the NDK, from pinned
  srclibs (`vosk-api`, `jna`, and Vosk's `kaldi`, `openfst`, `OpenBLAS`, `clapack`), through
  `scripts/build-native-deps.sh` and the Gradle switch `-Pwambito.nativeFromSource=true`. It runs
  in `build:` rather than `prebuild:` because the AARs it writes would otherwise be in the tree
  that the scanner reads between the two; their sources are scanned.
- The `arm64-v8a` entry also has the precise voice model's runtime: onnxruntime 1.28.2 and
  sherpa-onnx 2.0.1's JNI library, built in `build:` by `scripts/build-sherpa-onnx.sh` from 24
  srclibs pinned by commit (onnxruntime, sherpa-onnx and the 22 libraries their CMake would
  download). Nothing is downloaded during the build: onnxruntime's `cmake/deps.txt` is pointed at
  tars of those checkouts, and any URL left in it is made unusable. The switch
  `-Pwambito.preciseFromSource=true` adds the libraries and sherpa-onnx's Kotlin API sources. The
  `armeabi-v7a` entry has none of this.
- Gradle dependencies are locked (`gradle-fdroid.lockfile` for this build) and the Gradle wrapper
  jar is the official one for Gradle 9.3.1 (SHA-256 `b3a875dd...42ec13`).
- Tested locally with fdroidserver in the `buildserver` image: `fdroid lint`, `fdroid build`
  and `fdroid scanner` pass (`apps/mobile/scripts/fdroid-build-local.sh`). A build takes about an
  hour per ABI on four emulated cores; the recipe sets `timeout: 10800`.
- The app is signed by F-Droid with its own key. Users who move between F-Droid and our own APKs
  (GitHub or Google Play) have to reinstall.

## Runtime download: voice models

Dictation runs on the phone with Vosk. The speech models are not in the APK: on first use of the
microphone button, after an opt-in screen that shows the size, the app downloads one model for the
person's language (Spanish, English, Italian or Portuguese; Vosk small models, 30 to 50 MB). They
are data, not code, published by Alpha Cephei under Apache-2.0. The app downloads them from the
`voice-models-v1` release of the same GitHub repository and checks each file's SHA-256 (compiled
into the app) before unzipping or loading it; a mismatch is discarded. On `arm64-v8a` phones with
enough memory it also offers a more precise model in the same way (NVIDIA's Canary or Parakeet,
CC BY 4.0, converted to ONNX by the sherpa-onnx project; 150 or 478 MB), from the
`voice-models-v2` release. The person can delete the
model in Settings. Nothing else is downloaded or executed at runtime.

## Network and the default server

The app keeps the person's data on a Wambito server. By default that is `https://app.wambito.com`,
the author's own install of the server. The server is free software too (AGPL, in this repository:
`apps/api`, deployment in `deploy/personal`), and the person can change the address in Settings
(HTTPS only in release builds). Because the default server is the author's own install, anyone can create an
account on it unless the operator sets an allowlist; self-hosters decide for their own server.

## Anti-features

None declared:

- `NonFreeNet`: the network service it talks to is free software, its source is in this repository,
  and it can be self-hosted and selected in Settings.
- `Ads`, `Tracking`, `NonFreeDep`, `NonFreeAdd`, `UpstreamNonFree`: no ad,
  analytics or crash SDK; no Google or other proprietary dependency (checked in CI); the voice models are
  Apache-2.0 data.

If a reviewer reads the default server as `NonFreeNet`, we are happy to add it.

## Checklist

- [x] License AGPL-3.0-only, in the repo (`LICENSE`).
- [x] `fdroid lint` and `fdroid build` pass locally; `fdroid scanner` reports no problems.
- [x] Metadata in `fastlane` (en-US, es-ES, it-IT, pt-PT), changelogs per version code.
- [ ] `fdroid checkupdates` on the real tag (the tag `mobile-v1.0.0` must exist upstream before
      this merge request).
