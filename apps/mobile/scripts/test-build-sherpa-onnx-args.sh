#!/usr/bin/env bash
# Checks what scripts/build-sherpa-onnx.sh does before it needs a Linux host, its tools or the
# sources, so it runs anywhere in a second:
#   (a) with no --ndk it prints the usage, which lists --srclibs;
#   (b) an unknown option prints the usage (exit 2);
#   (c) with --ndk it gets past the arguments and stops at the next check, the host, a tool or the
#       NDK, with that check's own message;
#   (d) every pinned source is a full 40-character commit and appears once.
# The build itself checks its output (the ABI, what the JNI library links, onnxruntime's version);
# scripts/fdroid-build-local.sh runs it in F-Droid's image.
#
# Usage, from anywhere: apps/mobile/scripts/test-build-sherpa-onnx-args.sh
# Exit codes: 0 every check passed, 1 a check failed.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build-sherpa-onnx.sh"
failures=0
pass() { echo "ok    $1"; }
fail() {
  echo "FAIL  $1" >&2
  failures=$((failures + 1))
}

out="$("$SCRIPT" 2>&1 >/dev/null)"
code=$?
if [ "$code" -eq 2 ] && grep -q '^Usage' <<<"$out" && grep -q -- '\[--srclibs ' <<<"$out"; then
  pass "(a) no --ndk prints the usage, which lists --srclibs"
else
  fail "(a) no --ndk: exit $code, said: $out"
fi

out="$("$SCRIPT" --ndk /nonexistent --abi x86 2>&1 >/dev/null)"
code=$?
if [ "$code" -eq 2 ] && grep -q '^Usage' <<<"$out"; then pass "(b) an unknown option prints the usage"; else
  fail "(b) an unknown option: exit $code, said: $out"
fi

out="$("$SCRIPT" --ndk /nonexistent --srclibs /nonexistent 2>&1 >/dev/null)"
code=$?
if [ "$code" -eq 2 ] &&
  grep -q -E '^build-sherpa-onnx: (needs Linux x86_64 |[a-z0-9+]+ is missing\.$|cmake is |no NDK directory at )' <<<"$out"; then
  pass "(c) --ndk is taken (then: ${out%%$'\n'*})"
else
  fail "(c) --ndk: exit $code, said: $out"
fi

pins="$(grep '^pin ' "$SCRIPT")"
bad="$(awk '$3 !~ /^[0-9a-f]{40}$/ || $4 !~ /^https:\/\// || NF < 5' <<<"$pins")"
dupes="$(awk '{ print $2 }' <<<"$pins" | sort | uniq -d)"
if [ "$(grep -c . <<<"$pins")" -eq 24 ] && [ -z "$bad" ] && [ -z "$dupes" ]; then
  pass "(d) 24 pinned sources, each a full commit and a git URL, none twice"
else
  fail "(d) pins: $(grep -c . <<<"$pins") lines; malformed: $bad; twice: $dupes"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) of build-sherpa-onnx.sh failed." >&2
  exit 1
fi
echo "build-sherpa-onnx.sh's arguments behaved."
