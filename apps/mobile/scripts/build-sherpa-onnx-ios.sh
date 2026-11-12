#!/usr/bin/env bash
# Builds sherpa-onnx 2.0.1's iOS xcframework, for the on-device voice of the iOS app. k2-fsa
# publishes no iOS build of 2.0.1, so this runs upstream's own build-ios.sh, unchanged, at the pinned
# commit, with onnxruntime 1.28.2's static xcframework (csukuangfj/onnxruntime-libs) put where that
# script looks for it, so its own download is skipped and this pinned, checked file is used. It writes
# one zip, sherpa-onnx-ios-2.0.1.zip, holding
#   sherpa-onnx.xcframework   the C API (device arm64 and simulator arm64 + x86_64)
#   onnxruntime.xcframework   the runtime
#   SOURCES                   the commit, the onnxruntime file and its SHA-256, the Xcode version
# The zip goes in this repo's release ios-sherpa-onnx-2.0.1 and scripts/fetch-sherpa-onnx-ios.sh
# installs it, checked against its pinned SHA-256.
#
# Usage (macOS with Xcode, cmake, git, curl, zip; tens of minutes):
#   apps/mobile/scripts/build-sherpa-onnx-ios.sh
#       [--work <dir>]  the checkout and build trees, kept; default: a temporary one
#       [--out <file>]  default: sherpa-onnx-ios-2.0.1.zip in the current directory
# Exit codes: 0 built, 1 a build step failed, 2 bad arguments, host, tools or downloads.
set -euo pipefail

SHERPA_VERSION=2.0.1
SHERPA_COMMIT=af2d8d81dbfa61c4cea4c568da78f3982edca005 # v2.0.1
SHERPA_URL=https://github.com/k2-fsa/sherpa-onnx
ONNXRUNTIME_VERSION=1.28.2
ORT_ZIP="onnxruntime-ios-static-xcframework-$ONNXRUNTIME_VERSION.xcframework.zip"
ORT_URL="https://github.com/csukuangfj/onnxruntime-libs/releases/download/v$ONNXRUNTIME_VERSION/$ORT_ZIP"
ORT_SIZE=33821118
ORT_SHA256=2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599

work="" out="sherpa-onnx-ios-$SHERPA_VERSION.zip"

usage() {
  sed -n '/^# Usage/,/^# Exit codes/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}
die() {
  echo "build-sherpa-onnx-ios: $1" >&2
  exit "${2:-2}"
}
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --work) work="$2" ;;
    --out) out="$2" ;;
    *) usage ;;
  esac
  shift 2
done

[ "$(uname -s)" = Darwin ] || die "needs macOS with Xcode (this is $(uname -s))."
for tool in git cmake curl zip unzip shasum xcodebuild lipo libtool; do
  command -v "$tool" >/dev/null || die "$tool is missing."
done
xcode="$(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')"

mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
if [ -z "$work" ]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
fi
mkdir -p "$work"
work="$(cd "$work" && pwd)"
mkdir -p "$work/logs"

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
    echo "build-sherpa-onnx-ios: step $name failed (exit $status); the end of its log:" >&2
    tail -n 40 "$log" | sed 's/^/  | /' >&2
    die "step $name failed; the whole log is $log" 1
  fi
  echo "$(date -u +%H:%M:%S) $name done in $((SECONDS - start)) s" >&2
}

src="$work/sherpa-onnx"
fetch_source() {
  if [ ! -d "$src/.git" ]; then
    rm -rf "$src" && mkdir -p "$src"
    git -C "$src" init --quiet
    git -C "$src" fetch --quiet --depth 1 "$SHERPA_URL" "$SHERPA_COMMIT"
    git -C "$src" checkout --quiet FETCH_HEAD
  fi
  [ "$(git -C "$src" rev-parse HEAD)" = "$SHERPA_COMMIT" ]
}
step source fetch_source

# onnxruntime's zip, checked, where build-ios.sh looks for it (so its wget is skipped).
ort_dir="$src/build-ios/ios-onnxruntime/$ONNXRUNTIME_VERSION"
fetch_onnxruntime() {
  mkdir -p "$ort_dir"
  local zip="$work/$ORT_ZIP"
  [ -f "$zip" ] || curl --fail --location --silent --show-error --retry 3 -o "$zip" "$ORT_URL"
  [ "$(wc -c <"$zip" | tr -d ' ')" = "$ORT_SIZE" ] || { echo "onnxruntime zip: wrong size"; return 1; }
  [ "$(shasum -a 256 "$zip" | cut -d' ' -f1)" = "$ORT_SHA256" ] || { echo "onnxruntime zip: wrong SHA-256"; return 1; }
  rm -rf "$ort_dir/onnxruntime.xcframework"
  unzip -q "$zip" -d "$ort_dir"
  ln -sfn "$ONNXRUNTIME_VERSION/onnxruntime.xcframework" "$src/build-ios/ios-onnxruntime/onnxruntime.xcframework"
  [ -f "$ort_dir/onnxruntime.xcframework/ios-arm64/onnxruntime.framework/onnxruntime" ]
}
step onnxruntime fetch_onnxruntime

# Upstream's script, unchanged. It fetches sherpa-onnx's own C++ dependencies with CMake.
step build bash -c "cd '$src' && ./build-ios.sh"
[ -d "$src/build-ios/sherpa-onnx.xcframework" ] || die "build-ios.sh made no sherpa-onnx.xcframework." 1

pack() {
  rm -rf "$work/pack" && mkdir -p "$work/pack"
  cp -R "$src/build-ios/sherpa-onnx.xcframework" "$work/pack/"
  cp -R "$ort_dir/onnxruntime.xcframework" "$work/pack/"
  cat >"$work/pack/SOURCES" <<SRC
sherpa-onnx $SHERPA_VERSION for iOS, built by scripts/build-sherpa-onnx-ios.sh with upstream's build-ios.sh.
sherpa-onnx: $SHERPA_URL at $SHERPA_COMMIT (v$SHERPA_VERSION), Apache-2.0
onnxruntime: $ORT_URL
onnxruntime zip SHA-256: $ORT_SHA256 (MIT)
Xcode: $xcode
SRC
  rm -f "$out"
  (cd "$work/pack" && zip -q -r -y "$out" sherpa-onnx.xcframework onnxruntime.xcframework SOURCES)
}
step pack pack
echo "Built $out ($(shasum -a 256 "$out" | cut -d' ' -f1), $(wc -c <"$out" | tr -d ' ') bytes)."
