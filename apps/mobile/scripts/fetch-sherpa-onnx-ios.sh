#!/usr/bin/env bash
# Downloads sherpa-onnx's iOS build and installs it in ios/third_party/sherpa-onnx (git-ignored):
#   sherpa-onnx.xcframework   the C API (static, device and simulator) the Runner target links
#   onnxruntime.xcframework   the runtime it needs (static)
#   SOURCES                   what the build came from
# k2-fsa publishes no iOS build of sherpa-onnx 2.0.1, so scripts/build-sherpa-onnx-ios.sh builds it
# once with upstream's own build-ios.sh and the zip lives in this repo's release
# ios-sherpa-onnx-2.0.1. The headers are at sherpa-onnx.xcframework/*/Headers/sherpa-onnx/c-api/c-api.h.
#
# The file is checked against the pinned SHA-256 and size before anything is unzipped; a file that
# does not match is refused and nothing is written. The zip is unpacked into a staging folder and
# renamed into place, so an interrupted run never leaves half an install. Idempotent: an install that
# matches (the .sha256 file next to it) is left alone, one that does not is replaced.
#
# Usage, from anywhere: apps/mobile/scripts/fetch-sherpa-onnx-ios.sh [--from <file>] [--into <dir>]
#   --from <file>  use this local file instead of downloading (still checked)
#   --into <dir>   the folder to install into (default ios/third_party/sherpa-onnx)
# SHERPA_ONNX_IOS_SHA256 and SHERPA_ONNX_IOS_SIZE override the pinned values (for tests only).
# Exit codes: 0 installed (or already), 1 the file does not match, 2 the download or install failed.
set -euo pipefail

VERSION=2.0.1
URL="https://github.com/slinqer/wambito/releases/download/ios-sherpa-onnx-$VERSION/sherpa-onnx-ios-$VERSION.zip"
SIZE="${SHERPA_ONNX_IOS_SIZE:-50084228}"
SHA256="${SHERPA_ONNX_IOS_SHA256:-c1c3ab93cafc7c8b541e3ddeef87fda7fff11dc0be24de892a7e1c3f1ec08cdf}"

MOBILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTO="$MOBILE/ios/third_party/sherpa-onnx"
FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:?--from needs a file}"; shift 2 ;;
    --into) INTO="${2:?--into needs a directory}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
size_of() { wc -c <"$1" | tr -d ' '; }
matches() { [ "$(size_of "$1")" = "$SIZE" ] && [ "$(sha256_of "$1")" = "$SHA256" ]; }

MARK="$INTO.sha256"
if [ -f "$MARK" ] && [ "$(cat "$MARK")" = "$SHA256" ] && [ -d "$INTO/sherpa-onnx.xcframework" ] &&
  [ -d "$INTO/onnxruntime.xcframework" ] && [ -s "$INTO/SOURCES" ]; then
  echo "sherpa-onnx $VERSION for iOS is already in $INTO."
  exit 0
fi

TMP="$(mktemp -d)"
STAGE="$INTO.staging"
trap 'rm -rf "$TMP" "$STAGE"' EXIT
if [ -n "$FROM" ]; then
  cp "$FROM" "$TMP/sherpa.zip" || { echo "cannot read $FROM" >&2; exit 2; }
else
  curl --fail --location --silent --show-error --retry 3 -o "$TMP/sherpa.zip" "$URL" ||
    { echo "download of $URL failed" >&2; exit 2; }
fi
if ! matches "$TMP/sherpa.zip"; then
  echo "sherpa-onnx iOS zip refused: SHA-256 $(sha256_of "$TMP/sherpa.zip") ($(size_of "$TMP/sherpa.zip") bytes)," \
    "wanted $SHA256 ($SIZE bytes). Nothing was installed." >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
unzip -q "$TMP/sherpa.zip" -d "$STAGE" || { echo "cannot unzip the file" >&2; exit 2; }
for entry in sherpa-onnx.xcframework onnxruntime.xcframework SOURCES; do
  [ -e "$STAGE/$entry" ] || { echo "the zip has no $entry" >&2; exit 2; }
done
rm -rf "$INTO"
mv "$STAGE" "$INTO"
printf '%s\n' "$SHA256" >"$MARK.part"
mv "$MARK.part" "$MARK"
echo "Installed sherpa-onnx $VERSION for iOS into $INTO."
