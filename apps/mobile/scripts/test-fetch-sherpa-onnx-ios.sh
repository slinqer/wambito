#!/usr/bin/env bash
# Tests fetch-sherpa-onnx-ios.sh without the network, with --from <file> and --into <dir>:
#   - a file with the wrong SHA-256 is refused (exit 1) and leaves the target dir empty;
#   - a file with the wrong size is refused (exit 1);
#   - a file with the right SHA-256 and size installs sherpa-onnx.xcframework,
#     onnxruntime.xcframework and SOURCES, and a second run leaves the install alone.
# The script's pinned values are overridden with SHERPA_ONNX_IOS_SHA256 / SHERPA_ONNX_IOS_SIZE.
#
# Usage, from anywhere: apps/mobile/scripts/test-fetch-sherpa-onnx-ios.sh
# Exit codes: 0 every check passed, 1 a check failed.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH="$DIR/fetch-sherpa-onnx-ios.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "ok    $1"; }
fail() {
  echo "FAIL  $1" >&2
  failures=$((failures + 1))
}

# A stand-in zip: the two xcframeworks (empty) and SOURCES.
mkdir -p "$WORK/pack/sherpa-onnx.xcframework" "$WORK/pack/onnxruntime.xcframework"
printf 'a stand-in build\n' >"$WORK/pack/SOURCES"
(cd "$WORK/pack" && zip -q -r -y ../good.zip sherpa-onnx.xcframework onnxruntime.xcframework SOURCES)
printf 'not the real zip\n' >"$WORK/bad.zip"
good_sha="$(shasum -a 256 "$WORK/good.zip" | cut -d' ' -f1)"
good_size="$(wc -c <"$WORK/good.zip" | tr -d ' ')"
INTO="$WORK/into"

# 1. The wrong file (the pinned hash is the real zip's): refused, the fresh dir stays empty.
mkdir "$WORK/fresh"
out="$("$FETCH" --from "$WORK/bad.zip" --into "$WORK/fresh" 2>&1)"
code=$?
if [ "$code" -eq 1 ] && grep -qi 'sha-256' <<<"$out" && [ -z "$(ls -A "$WORK/fresh")" ]; then
  pass "a file with the wrong SHA-256 is refused and nothing is installed"
else
  fail "wrong file: exit $code, output: $out"
fi

# 2. The right hash with the wrong size: refused.
SHERPA_ONNX_IOS_SHA256="$good_sha" SHERPA_ONNX_IOS_SIZE=1 "$FETCH" --from "$WORK/good.zip" --into "$WORK/fresh" >/dev/null 2>&1
code=$?
if [ "$code" -eq 1 ] && [ -z "$(ls -A "$WORK/fresh")" ]; then
  pass "a file with the wrong size is refused"
else
  fail "wrong size: exit $code"
fi

# 3. The right file: installed (three entries).
export SHERPA_ONNX_IOS_SHA256="$good_sha" SHERPA_ONNX_IOS_SIZE="$good_size"
if "$FETCH" --from "$WORK/good.zip" --into "$INTO" >/dev/null 2>&1 &&
  [ -d "$INTO/sherpa-onnx.xcframework" ] && [ -d "$INTO/onnxruntime.xcframework" ] && [ -s "$INTO/SOURCES" ]; then
  pass "the right file installs both xcframeworks and SOURCES"
else
  fail "right file was not installed"
fi

# 4. Idempotent: a second run leaves the install alone.
before="$(stat -f %m "$INTO/SOURCES" 2>/dev/null || stat -c %Y "$INTO/SOURCES")"
sleep 1
if "$FETCH" --from "$WORK/good.zip" --into "$INTO" >/dev/null 2>&1 &&
  [ "$before" = "$(stat -f %m "$INTO/SOURCES" 2>/dev/null || stat -c %Y "$INTO/SOURCES")" ]; then
  pass "a second run leaves the install alone"
else
  fail "second run changed or failed"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed." >&2
  exit 1
fi
echo "fetch-sherpa-onnx-ios.sh behaved."
