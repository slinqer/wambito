# Spike: sherpa-onnx and onnxruntime from source, for F-Droid

Date: 2026-11-06. Question: can the precise voice model's runtime (sherpa-onnx 2.0.1 and onnxruntime
1.28.2, today a prebuilt AAR from a GitHub release, `scripts/fetch-sherpa-onnx.sh`) be built from
source in F-Droid's build image, so the F-Droid build gets Canary too (`docs/mobile/fdroid.md`,
"Open")? Answer: yes, for `arm64-v8a`. The libraries it builds give the same text as the official
ones on the founder's phone.

## What was built

All of it ran in `registry.gitlab.com/fdroid/fdroidserver:buildserver` (Debian 13, `linux/amd64`,
emulated on an Apple Silicon Mac), plus `cmake ninja-build g++ python3 unzip curl git` from apt
(cmake 3.31; onnxruntime needs ≥ 3.28) and NDK r28c (28.2.13676358, the recipe's).

1. **protoc 3.21.12 for the host**, from protobuf v21.12's source (CMake, `-Dprotobuf_BUILD_TESTS=OFF`).
   onnxruntime would otherwise download a prebuilt protoc (`deps.txt`, `protoc_linux_x64`).
2. **onnxruntime v1.28.2** (commit 33ca962), `arm64-v8a`, API 26:

   ```
   python3 tools/ci_build/build.py --build_dir <dir> --config Release --update --build \
     --android --android_abi arm64-v8a --android_api 26 --android_sdk_path <any> \
     --android_ndk_path <ndk> --build_shared_lib --parallel 10 --skip_tests \
     --skip_submodule_sync --cmake_generator Ninja --path_to_protoc_exe <host protoc> \
     --compile_no_warning_as_error --allow_running_as_root --skip_pip_install \
     --cmake_extra_defines onnxruntime_BUILD_UNIT_TESTS=OFF
   ```

   `--allow_running_as_root` because the container runs as root; `--android_sdk_path` is not used
   for a library build (a missing folder worked). 76 minutes on 10 emulated cores.
3. **sherpa-onnx v2.0.1** (commit af2d8d8), the JNI library only, against that onnxruntime:
   `SHERPA_ONNXRUNTIME_INCLUDE_DIR` (onnxruntime's `include/onnxruntime/core/session/*.h`) and
   `SHERPA_ONNXRUNTIME_LIB_DIR` (its `libonnxruntime.so`), and CMake with
   `-DSHERPA_ONNX_ENABLE_JNI=ON`, `TTS`, `SPEAKER_DIARIZATION`, `BINARY`, `C_API`, `PYTHON`, `TESTS`,
   `CHECK`, `PORTAUDIO`, `WEBSOCKET` and `GPU` all `OFF`. 3 minutes.

## Result

| | official AAR (arm64-v8a) | from source |
|---|---|---|
| `libonnxruntime.so` | 22 249 560 bytes | 20 875 712 bytes |
| `libsherpa-onnx-jni.so` (stripped) | 4 609 320 bytes | 3 844 888 bytes (no TTS) |
| `libsherpa-onnx-c-api.so`, `-cxx-api.so` | shipped | not built (the Kotlin API loads only the JNI one) |
| NNAPI execution provider | in | out (the default build has none; sherpa-onnx only calls it for API ≥ 27 builds and the app uses the CPU) |

`libsherpa-onnx-jni.so` needs only `OrtGetApiBase` from onnxruntime, plus `libandroid`, `liblog`,
`libm`, `libdl`, `libc`.

On the S25 Ultra, the replay tool (`wambito-sim-stream`, the 19 Spanish phrases, a pass every
0.5 s, 4 threads), rebuilt in the same container against the from-source onnxruntime:

| | final texts | all 93 passes | decode median | p90 | max |
|---|---|---|---|---|---|
| official onnxruntime | — | — | 88 ms | 139 ms | 247 ms |
| from source | 19/19 identical | 93/93 identical | 92 ms | 125 ms | 182 ms |

Not tested: the from-source JNI library inside the app (the replay tool links sherpa-onnx's C++
directly), `armeabi-v7a`, and the build on F-Droid's own server.

## What the build fetches

Everything below is downloaded by CMake at configure time. In F-Droid each becomes a pinned srclib
(or a tarball checked by hash), handed over without network.

onnxruntime (`cmake/deps.txt`; with `--cmake_deps_mirror_dir <dir>` it reads them from a folder laid
out like the URLs instead of downloading):

| dep | version |
|---|---|
| abseil-cpp | 20250814.0 |
| date | v3.0.1 |
| eigen (eigen-mirror) | 1d8b82b |
| flatbuffers | v23.5.26 |
| GSL | v4.2.1 |
| kleidiai | v1.20.0 |
| mp11 | boost-1.82.0 |
| nlohmann/json | v3.11.3 |
| onnx | v1.22.0 |
| protobuf | v21.12 (also built for the host, for protoc) |
| cpuinfo (pytorch) | 4628dc0 |
| re2 | 2024-07-02 |
| SafeInt | 3.0.28 |

sherpa-onnx (`cmake/*.cmake`, each with a SHA-256; each also looks for the tarball in a few local
folders first, e.g. `$HOME/Downloads`, which is the offline hook): kaldi-native-fbank v1.22.4,
kissfft febd4ca (pulled by kaldi-native-fbank), utf8proc v2.12.0, kaldi-decoder v0.3.0, kaldifst
v1.8.0, openfst v1.8.5-2026-07-09, eigen 5.0.1, simple-sentencepiece v0.7, nlohmann/json v3.12.0.

That is 22 sources besides onnxruntime and sherpa-onnx themselves, against six srclibs today.

## Findings

- **API level.** onnxruntime has to be built for the app's `minSdk` (26) or lower. Built for 26 it
  references libc symbols that API 21 stubs lack, so an executable linked at 21 fails to link. A
  shared library links anyway, so sherpa-onnx's own default of `android-21` hid it. The recipe
  should pass 26 to both.
- **Licences in About.** The official AAR's `libonnxruntime.so` also contains KleidiAI (Arm's
  strings are in both builds), and onnxruntime links cpuinfo, flatbuffers, SafeInt, GSL, date,
  mp11 and Eigen. About lists only Abseil, ONNX, Protocol Buffers and RE2 for it
  (`lib/settings/licenses.dart`). kissfft (BSD-3-Clause) goes into the JNI library through
  kaldi-native-fbank and is not listed either. This gap exists today, in the Play/GitHub build,
  whatever F-Droid does.
- **Build time.** 76 minutes for onnxruntime on emulated cores, on top of the 30 for Vosk and JNA
  and the Flutter build: the recipe's `timeout: 10800` (3 hours) is tight per ABI on a slow server.
  A smaller onnxruntime (`--minimal_build` with an operator config for the two models,
  `--disable_ml_ops`, `--disable_contrib_ops` if Canary and Parakeet allow) would cut both time and
  size. Not tried.
- **ABIs.** Canary only runs on `arm64-v8a` (`PreciseModels.qualifies`). The `armeabi-v7a` F-Droid
  entry can stay without sherpa-onnx (`src/noPrecise`), which saves its build the 80 minutes.

## Proposal for the recipe (not done)

1. Extend `build-native-deps.sh` with `--with-sherpa` (arm64-v8a only): build host protoc, onnxruntime
   with `--cmake_deps_mirror_dir` pointed at the srclibs, then sherpa-onnx with
   `SHERPA_ONNXRUNTIME_*`; compile sherpa-onnx's `kotlin-api` sources into the classes jar; write
   `com.k2fsa.sherpa.onnx:sherpa-onnx:2.0.1-src` to `android/third_party/m2` like the Vosk and JNA
   artifacts.
2. With the switch, the arm64 F-Droid entry takes `2.0.1-src` and `src/precise`; the
   `armeabi-v7a` entry keeps `src/noPrecise`. `gradle-fdroid.lockfile` and `check-fdroid-lock.sh`
   follow.
3. Add the 24 sources to `apps/mobile/fdroid/srclibs/`, all pinned by commit, and keep them in step
   with sherpa-onnx's and onnxruntime's pins through `check-fdroid-recipe.sh`.
4. Fix the About gap above first, in its own change.
5. Then a full `fdroid-build-local.sh` run of the arm64 entry, and the app on the phone.

The spike's scripts (the Dockerfile, `build-ort.sh`, `build-sherpa.sh`, `build-sim.sh`) were
scratch files and are not kept; their commands are above.
