#!/usr/bin/env bash
# Builds the precise voice model's runtime from source, for the F-Droid build: onnxruntime 1.28.2
# (libonnxruntime.so) and sherpa-onnx 2.0.1's JNI library (libsherpa-onnx-jni.so, without TTS or
# speaker diarization), for arm64-v8a only (the only ABI the precise model runs on,
# PreciseModels.qualifies). The Play and GitHub builds take k2-fsa's prebuilt AAR instead
# (scripts/fetch-sherpa-onnx.sh); F-Droid takes no prebuilt binary. It writes
#   <out>/jniLibs/arm64-v8a/{libonnxruntime.so,libsherpa-onnx-jni.so}
#   <out>/kotlin/com/k2fsa/sherpa/onnx/*.kt   the Kotlin API, the files k2-fsa's AAR is built from
#                                             (android/SherpaOnnxAar's links into kotlin-api/)
#   <out>/SOURCES                             every source and its revision
# and the app compiles and packs them with `-Pwambito.preciseFromSource=true`
# (android/app/build.gradle.kts). The recipe is the spike's
# (docs/superpowers/reports/2026-11-06-sherpa-onnx-from-source-spike.md).
#
# Nothing is downloaded: every source, the 22 that onnxruntime's and sherpa-onnx's CMake would fetch
# included, is a git checkout at the revision pinned below (in F-Droid, one srclib each, all under
# one folder). onnxruntime reads its dependencies from cmake/deps.txt (URL and SHA-1 of an archive)
# and patches some of them: each pinned one becomes a local tar of its checkout, with that tar's
# SHA-1, so its patches still apply, and every URL left in deps.txt is made unusable, so a
# dependency this script does not know fails the build instead of reaching the network.
# sherpa-onnx's CMake takes each of its own as FETCHCONTENT_SOURCE_DIR_<NAME>.
#
# Usage (Linux x86_64 with the NDK below, cmake >= 3.28, ninja, g++, python3, git, tar; about an
# hour and a half on 10 cores):
#   apps/mobile/scripts/build-sherpa-onnx.sh --ndk <dir>
#       [--srclibs <dir>]  a folder with each source below in a subfolder named after it (F-Droid's
#                          build/srclib); each one missing there is fetched with git at its
#                          pinned revision
#       [--out <dir>]      default: apps/mobile/android/third_party/sherpa-onnx-src
#       [--work <dir>]     the build trees (about 6 GB), kept; default: a temporary one
#       [--jobs <n>]       default: the number of processors
# Every source must be a git checkout at its pinned revision, at a path with no spaces.
# Exit codes: 0 built, 1 a build step failed, 2 bad arguments, host, tools or sources.
set -euo pipefail

NDK_VERSION=28.2.13676358 # r28c, as scripts/build-native-deps.sh
ANDROID_API=26            # the app's minSdk: onnxruntime built for it needs libc symbols API 21 lacks
ABI=arm64-v8a
SHERPA_VERSION=2.0.1
ONNXRUNTIME_VERSION=1.28.2

# Pinned sources, one line each: pin <srclib name> <commit> <git url> <what uses it>, where the
# last field is ort:<name in onnxruntime's cmake/deps.txt>, sherpa:<FetchContent name in
# sherpa-onnx's cmake> (sherpa-onnx's own, or one of its dependencies'), or a role. The F-Droid
# recipe's arm64-v8a entry lists each as <srclib name>@<commit> (scripts/check-fdroid-recipe.sh).
PINS=()
pin() { PINS+=("$*"); }
pin onnxruntime 33ca9628233dc8f002435e868d4c2e9f82766ca1 https://github.com/microsoft/onnxruntime onnxruntime          # v1.28.2
pin sherpa-onnx af2d8d81dbfa61c4cea4c568da78f3982edca005 https://github.com/k2-fsa/sherpa-onnx sherpa-onnx            # v2.0.1
pin abseil-cpp 987c57f325f7fa8472fa84e1f885f7534d391b0d https://github.com/abseil/abseil-cpp ort:abseil_cpp          # 20250814.0
pin hinnant-date 6e921e1b1d21e84a5c82416ba7ecd98e33a436d0 https://github.com/HowardHinnant/date ort:date             # v3.0.1
pin eigen-mirror 1d8b82b0740839c0de7f1242a3585e3390ff5f33 https://github.com/eigen-mirror/eigen ort:eigen
pin flatbuffers 0100f6a5779831fa7a651e4b67ef389a8752bd9b https://github.com/google/flatbuffers ort:flatbuffers       # v23.5.26
pin GSL 249146590e322123cd0b378b1f364d6069717687 https://github.com/microsoft/GSL ort:microsoft_gsl                   # v4.2.1
pin kleidiai 4d2725c91ffcb1ae674196b98660d69d4084bf4f https://github.com/ARM-software/kleidiai ort:kleidiai           # v1.20.0
pin mp11 0a0b5fb001ce0233ae3a6f99d849c0649e5a7361 https://github.com/boostorg/mp11 ort:mp11                          # boost-1.82.0
pin nlohmann-json-3.11 9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03 https://github.com/nlohmann/json ort:json             # v3.11.3
pin onnx 2bb50465112feca9003e1ed654d77f01ff1415ca https://github.com/onnx/onnx ort:onnx                              # v1.22.0
pin protobuf f0dc78d7e6e331b8c6bb2d5283e06aa26883ca7c https://github.com/protocolbuffers/protobuf ort:protobuf       # v21.12, also the host protoc
pin cpuinfo 4628dc060ce4e82345dc166bbac875609db4ff69 https://github.com/pytorch/cpuinfo ort:pytorch_cpuinfo
pin re2 6dcd83d60f7944926bfd308cc13979fc53dd69ca https://github.com/google/re2 ort:re2                                # 2024-07-02
pin SafeInt 4cafc9196c4da9c817992b20f5253ef967685bf8 https://github.com/dcleblanc/SafeInt ort:safeint                 # 3.0.28
pin kaldi-native-fbank 95032e2223c73addc965bb84d2d1b11498eda4e9 https://github.com/csukuangfj/kaldi-native-fbank sherpa:kaldi_native_fbank # v1.22.4
pin kissfft febd4caeed32e33ad8b2e0bb5ea77542c40f18ec https://github.com/mborgerding/kissfft sherpa:kissfft
pin utf8proc 79cdd5ab40c79afa559f689ffc13b76812dee1ac https://github.com/JuliaStrings/utf8proc sherpa:utf8proc       # v2.12.0
pin kaldi-decoder 62fda2d74246a90db9570e46fb16b012f813fae7 https://github.com/k2-fsa/kaldi-decoder sherpa:kaldi_decoder # v0.3.0
pin kaldifst ab5bdd013bdf13921e6aeee77db5722ebf9955fb https://github.com/k2-fsa/kaldifst sherpa:kaldifst              # v1.8.0
pin openfst-csukuangfj f702a6317d600ac953fdbb4978674c3a28b6115c https://github.com/csukuangfj/openfst sherpa:openfst # v1.8.5-2026-07-09
pin eigen bc3b39870ecb690a623a3f49149a358b95c5781d https://gitlab.com/libeigen/eigen sherpa:eigen                    # 5.0.1
pin simple-sentencepiece 62dd423df1d51da5ea06f1c3a046fc04f01b4f39 https://github.com/pkufool/simple-sentencepiece sherpa:simple-sentencepiece # v0.7
pin nlohmann-json 55f93686c01528224f448c19128836e7df245f72 https://github.com/nlohmann/json sherpa:json               # v3.12.0

MOBILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ndk="" srclibs="" out="$MOBILE/android/third_party/sherpa-onnx-src" work="" jobs=""

usage() {
  sed -n '/^# Usage/,/^# Exit codes/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}
die() {
  echo "build-sherpa-onnx: $1" >&2
  exit "${2:-2}"
}
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --ndk) ndk="$2" ;;
    --srclibs) srclibs="$2" ;;
    --out) out="$2" ;;
    --work) work="$2" ;;
    --jobs) jobs="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$ndk" ] || usage

[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] ||
  die "needs Linux x86_64 (this is $(uname -s) $(uname -m)): run it in a linux/amd64 container."
for tool in git cmake ninja g++ python3 tar sha1sum; do
  command -v "$tool" >/dev/null || die "$tool is missing."
done
cmake_have="$(cmake --version | sed -n 's/^cmake version \([0-9]*\.[0-9]*\).*/\1/p')"
printf '%s\n%s\n' 3.28 "$cmake_have" | sort -V -C || die "cmake is $cmake_have; onnxruntime needs 3.28 or later."
ndk="$(cd "$ndk" 2>/dev/null && pwd)" || die "no NDK directory at $ndk"
ndk_have="$(sed -n 's/^Pkg\.Revision *= *//p' "$ndk/source.properties" 2>/dev/null || true)"
[ "$ndk_have" = "$NDK_VERSION" ] || die "the NDK at $ndk is '${ndk_have:-unknown}', not $NDK_VERSION."
ndk_bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
[ -x "$ndk_bin/clang" ] || die "the NDK at $ndk has no linux-x86_64 toolchain."
jobs="${jobs:-$(nproc)}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive number."

if [ -z "$work" ]; then
  work="$(mktemp -d)"
  trap 'status=$?
    if [ "$status" -eq 0 ]; then rm -rf "$work"
    else
      find "$work" -mindepth 1 -maxdepth 1 ! -name logs -exec rm -rf {} +
      echo "build-sherpa-onnx: the logs are kept in $work/logs" >&2
    fi' EXIT
fi
mkdir -p "$work"
work="$(cd "$work" && pwd)"
mkdir -p "$work/src" "$work/logs"

# source_dir <name> <revision> <git url>: the absolute directory of a source, from --srclibs or
# fetched into the work folder, checked against its revision.
source_dir() {
  local name="$1" rev="$2" url="$3" dir have
  dir="${srclibs:+$srclibs/$name}"
  if [ -z "$dir" ] || [ ! -e "$dir" ]; then
    dir="$work/src/$name"
    if [ ! -d "$dir/.git" ]; then
      echo "Fetching $name at $rev" >&2
      rm -rf "$dir" && mkdir -p "$dir"
      git -C "$dir" init --quiet
      git -C "$dir" fetch --quiet --depth 1 "$url" "$rev" || die "could not fetch $name from $url."
      git -C "$dir" checkout --quiet FETCH_HEAD
    fi
  fi
  dir="$(cd "$dir" 2>/dev/null && pwd)" || die "no $name source at $dir"
  case "$dir" in *[[:space:]]* | *';'*) die "the path of $name may not hold spaces or ;: $dir" ;; esac
  [ -e "$dir/.git" ] ||
    die "$name at $dir is not a git checkout, so its revision cannot be checked against $rev."
  have="$(git -c safe.directory='*' -C "$dir" rev-parse HEAD 2>/dev/null || true)"
  [ "$have" = "$rev" ] || die "$name at $dir is at '${have:-unknown}', not the pinned $rev."
  echo "$dir"
}
declare -A SRC
for line in "${PINS[@]}"; do
  read -r name rev url _ <<<"$line"
  SRC[$name]="$(source_dir "$name" "$rev" "$url")"
done
[ -f "${SRC[onnxruntime]}/tools/ci_build/build.py" ] || die "${SRC[onnxruntime]} is not onnxruntime."
[ -d "${SRC[sherpa-onnx]}/sherpa-onnx/kotlin-api" ] || die "${SRC[sherpa-onnx]} is not sherpa-onnx."

# step <name> <command...>: a build step into its own log; on failure, its end and where it is.
step() {
  local name="$1" log="$work/logs/$1.log" start=$SECONDS status
  shift
  echo "$(date -u +%H:%M:%S) $name..." >&2
  set +e
  (
    set -e
    "$@"
  ) >"$log" 2>&1
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "build-sherpa-onnx: step $name failed (exit $status); the end of its log:" >&2
    tail -n 40 "$log" | sed 's/^/  | /' >&2
    die "step $name failed; the whole log is $log" 1
  fi
  echo "$(date -u +%H:%M:%S) $name done in $((SECONDS - start)) s" >&2
}

# --- protoc for this machine, from the same protobuf onnxruntime builds for Android ---------------
protoc_host() {
  rm -rf "$work/protoc-build" "$work/protoc"
  cmake -S "${SRC[protobuf]}" -B "$work/protoc-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$work/protoc"
  cmake --build "$work/protoc-build" --target install -j "$jobs"
}
step protoc protoc_host
[ -x "$work/protoc/bin/protoc" ] || die "no host protoc was built." 1

# --- onnxruntime, its dependencies from the pinned checkouts -------------------------------------
ort="$work/onnxruntime"
onnxruntime() {
  rm -rf "$ort" "$work/ort-build" "$work/mirror"
  cp -a "${SRC[onnxruntime]}" "$ort"
  mkdir -p "$work/mirror"
  local deps="$ort/cmake/deps.txt" line name use dep tarball sha1
  for line in "${PINS[@]}"; do
    read -r name _ _ use <<<"$line"
    [[ "$use" == ort:* ]] || continue
    dep="${use#ort:}"
    grep -q "^$dep;" "$deps" || die "onnxruntime's deps.txt has no $dep." 1
    tarball="$work/mirror/$dep.tar"
    tar -C "${SRC[$name]}" --exclude=.git --sort=name --owner=0 --group=0 --numeric-owner \
      --mtime=@0 -cf "$tarball" .
    sha1="$(sha1sum "$tarball" | cut -d' ' -f1)"
    sed -i "s#^$dep;[^;]*;[0-9a-f]*\$#$dep;$tarball;$sha1#" "$deps"
    grep -qx "$dep;$tarball;$sha1" "$deps" || die "could not point deps.txt's $dep at $tarball." 1
  done
  # Whatever is still a URL is a dependency this script does not provide: unusable, not fetched.
  sed -i 's#;https://[^;]*;#;/nonexistent/not-provided-by-build-sherpa-onnx;#' "$deps"
  ! grep -v '^#' "$deps" | grep -q 'https://' || die "deps.txt still has a URL." 1
  (cd "$ort" && python3 tools/ci_build/build.py --build_dir "$work/ort-build" --config Release \
    --update --build --android --android_abi "$ABI" --android_api "$ANDROID_API" \
    --android_sdk_path "$work/no-sdk" --android_ndk_path "$ndk" --build_shared_lib \
    --parallel "$jobs" --skip_tests --skip_submodule_sync --cmake_generator Ninja \
    --path_to_protoc_exe "$work/protoc/bin/protoc" --compile_no_warning_as_error \
    --allow_running_as_root --skip_pip_install \
    --cmake_extra_defines onnxruntime_BUILD_UNIT_TESTS=OFF FETCHCONTENT_TRY_FIND_PACKAGE_MODE=NEVER)
}
step onnxruntime onnxruntime
ort_so="$work/ort-build/Release/libonnxruntime.so"
[ -f "$ort_so" ] || die "no libonnxruntime.so was built." 1

# --- sherpa-onnx's JNI library, against that onnxruntime -----------------------------------------
sherpa() {
  rm -rf "$work/sherpa-build" "$work/ort-stage"
  mkdir -p "$work/ort-stage/include" "$work/ort-stage/lib"
  cp "$ort"/include/onnxruntime/core/session/*.h "$work/ort-stage/include/"
  cp "$ort_so" "$work/ort-stage/lib/"
  # Copies of the checkouts: sherpa-onnx's CMake edits some of them in place (simple-sentencepiece).
  local line name use args=()
  rm -rf "$work/sherpa-deps" && mkdir -p "$work/sherpa-deps"
  for line in "${PINS[@]}"; do
    read -r name _ _ use <<<"$line"
    [[ "$use" == sherpa:* ]] || continue
    cp -a "${SRC[$name]}" "$work/sherpa-deps/$name"
    rm -rf "$work/sherpa-deps/$name/.git"
    args+=("-DFETCHCONTENT_SOURCE_DIR_$(tr '[:lower:]' '[:upper:]' <<<"${use#sherpa:}")=$work/sherpa-deps/$name")
  done
  SHERPA_ONNXRUNTIME_INCLUDE_DIR="$work/ort-stage/include" SHERPA_ONNXRUNTIME_LIB_DIR="$work/ort-stage/lib" \
    cmake -S "${SRC[sherpa-onnx]}" -B "$work/sherpa-build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="android-$ANDROID_API" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DSHERPA_ONNX_ENABLE_JNI=ON \
    -DSHERPA_ONNX_ENABLE_TTS=OFF -DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF \
    -DSHERPA_ONNX_ENABLE_BINARY=OFF -DSHERPA_ONNX_ENABLE_C_API=OFF -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
    -DSHERPA_ONNX_ENABLE_TESTS=OFF -DSHERPA_ONNX_ENABLE_CHECK=OFF -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
    -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF -DSHERPA_ONNX_ENABLE_GPU=OFF "${args[@]}"
  # Every dependency came from a pinned checkout: CMake populated nothing of its own (it prints
  # "Downloading ..." either way). FULLY_DISCONNECTED above makes one it would fetch fail instead.
  local fetched
  fetched="$(find "$work/sherpa-build/_deps" -mindepth 1 -maxdepth 1 -name '*-src' 2>/dev/null)"
  [ -z "$fetched" ] || { echo "CMake populated: $fetched" >&2; exit 1; }
  cmake --build "$work/sherpa-build" --target sherpa-onnx-jni -j "$jobs"
}
step sherpa-onnx sherpa
jni_so="$(find "$work/sherpa-build" -name libsherpa-onnx-jni.so -type f | head -n 1)"
[ -n "$jni_so" ] || die "no libsherpa-onnx-jni.so was built." 1

# --- Checks, then into place -------------------------------------------------------------------
stage="$work/stage"
rm -rf "$stage" && mkdir -p "$stage/jniLibs/$ABI" "$stage/kotlin/com/k2fsa/sherpa/onnx"
for so in "$ort_so" "$jni_so"; do
  "$ndk_bin/llvm-strip" --strip-unneeded -o "$stage/jniLibs/$ABI/$(basename "$so")" "$so"
done
for so in "$stage/jniLibs/$ABI"/*.so; do
  machine="$("$ndk_bin/llvm-readelf" -h "$so" | sed -n 's/^ *Machine: *//p')"
  [ "$machine" = AArch64 ] || die "$so is built for '$machine', not AArch64." 1
done
# The JNI library takes onnxruntime through its C API only, and nothing outside Android's own
# libraries and onnxruntime.
needed="$("$ndk_bin/llvm-readelf" -d "$stage/jniLibs/$ABI/libsherpa-onnx-jni.so" |
  sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | LC_ALL=C sort | tr '\n' ' ')"
[ "$needed" = "libandroid.so libc.so libdl.so liblog.so libm.so libonnxruntime.so " ] ||
  die "libsherpa-onnx-jni.so needs '$needed'." 1
"$ndk_bin/llvm-nm" -D --defined-only "$stage/jniLibs/$ABI/libonnxruntime.so" |
  grep -q " OrtGetApiBase@@VERS_$ONNXRUNTIME_VERSION\$" || die "libonnxruntime.so is not $ONNXRUNTIME_VERSION." 1

# The Kotlin API, as k2-fsa's AAR project (android/SherpaOnnxAar) links it from kotlin-api/.
aar_java="${SRC[sherpa-onnx]}/android/SherpaOnnxAar/sherpa_onnx/src/main/java/com/k2fsa/sherpa/onnx"
[ -d "$aar_java" ] || die "sherpa-onnx has no android/SherpaOnnxAar sources." 1
for link in "$aar_java"/*.kt; do
  cp "${SRC[sherpa-onnx]}/sherpa-onnx/kotlin-api/$(basename "$link")" "$stage/kotlin/com/k2fsa/sherpa/onnx/"
done
[ -f "$stage/kotlin/com/k2fsa/sherpa/onnx/OfflineRecognizer.kt" ] || die "no OfflineRecognizer.kt." 1

{
  echo "sherpa-onnx $SHERPA_VERSION and onnxruntime $ONNXRUNTIME_VERSION for $ABI, API $ANDROID_API, NDK $NDK_VERSION"
  for line in "${PINS[@]}"; do read -r name rev url _ <<<"$line" && echo "$name $rev $url"; done
} >"$stage/SOURCES"

rm -rf "${out:?}"
mkdir -p "$(dirname "$out")"
cp -R "$stage" "$out"
echo "Wrote sherpa-onnx $SHERPA_VERSION and onnxruntime $ONNXRUNTIME_VERSION ($ABI) to $out" >&2
