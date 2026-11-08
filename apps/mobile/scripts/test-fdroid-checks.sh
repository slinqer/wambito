#!/usr/bin/env bash
# Tests check-fdroid-recipe.sh and check-fdroid-lock.sh: each passes on the committed files and
# fails (exit 1, naming the problem) on a copy with one deliberate mismatch. Text only, so it runs
# anywhere in a second.
#
# Usage, from anywhere: apps/mobile/scripts/test-fdroid-checks.sh
# Exit codes: 0 every check passed, 1 a check failed.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE="$(cd "$DIR/.." && pwd)"
RECIPE="$MOBILE/fdroid/com.wambito.app.yml"
DEPS="$DIR/build-native-deps.sh"
SHERPA="$DIR/build-sherpa-onnx.sh"
SRCLIBS="$MOBILE/fdroid/srclibs"
FLUTTER="$MOBILE/.flutter-version"
LOCK="$MOBILE/android/app/gradle.lockfile"
FLOCK="$MOBILE/android/app/gradle-fdroid.lockfile"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "ok    $1"; }
fail() {
  echo "FAIL  $1" >&2
  failures=$((failures + 1))
}

# expect <name> <exit code> <text the output must hold> <command...>
expect() {
  local name="$1" want="$2" text="$3" out code
  shift 3
  out="$("$@" 2>&1)"
  code=$?
  if [ "$code" -eq "$want" ] && grep -qF -- "$text" <<<"$out"; then
    pass "$name"
  else
    fail "$name: exit $code (wanted $want), said: $out"
  fi
}

recipe_check() {
  RECIPE="$1" DEPS="$2" FLUTTER_VERSION_FILE="$3" SHERPA="${4:-$SHERPA}" SRCLIBS="${5:-$SRCLIBS}" \
    "$DIR/check-fdroid-recipe.sh"
}
lock_check() { LOCK="$1" FDROID_LOCK="$2" "$DIR/check-fdroid-lock.sh"; }

# --- the recipe ---
expect "recipe: committed files agree" 0 "agrees" recipe_check "$RECIPE" "$DEPS" "$FLUTTER"

echo "3.99.0" >"$WORK/flutter-version"
expect "recipe: a Flutter version that differs is caught" 1 "flutter@3.99.0" \
  recipe_check "$RECIPE" "$DEPS" "$WORK/flutter-version"

sed 's/^\(KALDI_REV=\)8b7f/\10000/' "$DEPS" >"$WORK/deps-kaldi.sh"
expect "recipe: a srclib revision that differs is caught" 1 "kaldi" \
  recipe_check "$RECIPE" "$WORK/deps-kaldi.sh" "$FLUTTER"

sed 's/^JNA_VERSION=5.18.1-src/JNA_VERSION=5.19.0-src/' "$DEPS" >"$WORK/deps-jna.sh"
expect "recipe: a JNA version that differs is caught" 1 "jna" \
  recipe_check "$RECIPE" "$WORK/deps-jna.sh" "$FLUTTER"

# Only the second build entry drifts.
awk '/openfst@/ { n++; if (n == 2) sub(/openfst@18e94e/, "openfst@000000") } { print }' "$RECIPE" >"$WORK/recipe-second.yml"
expect "recipe: drift in only one build entry is caught" 1 "openfst" \
  recipe_check "$WORK/recipe-second.yml" "$DEPS" "$FLUTTER"

sed 's/^    ndk: r28c$/    ndk: r27/' "$RECIPE" >"$WORK/recipe-ndk.yml"
expect "recipe: an NDK that differs is caught" 1 "ndk" \
  recipe_check "$WORK/recipe-ndk.yml" "$DEPS" "$FLUTTER"

# The precise model's sources: in the arm64-v8a entry only, at build-sherpa-onnx.sh's revisions.
sed 's/^\(pin kissfft \)febd4c/\1000000/' "$SHERPA" >"$WORK/sherpa-rev.sh"
expect "recipe: a sherpa-onnx source revision that differs is caught" 1 "kissfft" \
  recipe_check "$RECIPE" "$DEPS" "$FLUTTER" "$WORK/sherpa-rev.sh"

grep -v '^      - re2@' "$RECIPE" >"$WORK/recipe-no-re2.yml"
expect "recipe: a source missing from the arm64-v8a entry is caught" 1 "re2" \
  recipe_check "$WORK/recipe-no-re2.yml" "$DEPS" "$FLUTTER"

awk '/^      - clapack@/ && !done { print; print "      - kissfft@febd4caeed32e33ad8b2e0bb5ea77542c40f18ec"; done = 1; next } { print }' \
  "$RECIPE" >"$WORK/recipe-v7a-kissfft.yml"
expect "recipe: a sherpa-onnx source in the armeabi-v7a entry is caught" 1 "armeabi-v7a" \
  recipe_check "$WORK/recipe-v7a-kissfft.yml" "$DEPS" "$FLUTTER"

sed 's/ -P wambito\.preciseFromSource=true//' "$RECIPE" >"$WORK/recipe-no-precise.yml"
expect "recipe: an arm64-v8a build without the precise switch is caught" 1 "wambito.preciseFromSource" \
  recipe_check "$WORK/recipe-no-precise.yml" "$DEPS" "$FLUTTER"

cp -R "$SRCLIBS" "$WORK/srclibs"
printf 'RepoType: git\nRepo: https://github.com/example/kissfft.git\n' >"$WORK/srclibs/kissfft.yml"
expect "recipe: a srclib file whose repository differs is caught" 1 "kissfft" \
  recipe_check "$RECIPE" "$DEPS" "$FLUTTER" "$SHERPA" "$WORK/srclibs"
rm "$WORK/srclibs/kissfft.yml"
expect "recipe: a missing srclib file is caught" 1 "kissfft" \
  recipe_check "$RECIPE" "$DEPS" "$FLUTTER" "$SHERPA" "$WORK/srclibs"

sed 's/^NDK_VERSION=28.2.13676358/NDK_VERSION=27.0.12077973/' "$SHERPA" >"$WORK/sherpa-ndk.sh"
expect "recipe: a build-sherpa-onnx.sh NDK that differs is caught" 1 "NDK" \
  recipe_check "$RECIPE" "$DEPS" "$FLUTTER" "$WORK/sherpa-ndk.sh"

# --- the lock ---
expect "lock: committed locks agree" 0 "equals" lock_check "$LOCK" "$FLOCK"

sed 's/^net\.java\.dev\.jna:jna:5\.18\.1-src=/net.java.dev.jna:jna:5.18.1=/' "$FLOCK" >"$WORK/lock-plain.txt"
expect "lock: a fdroid lock with a plain JNA is caught" 1 "gradle-fdroid.lockfile" \
  lock_check "$LOCK" "$WORK/lock-plain.txt"

grep '^com\.k2fsa\.sherpa\.onnx:sherpa-onnx:' "$LOCK" >"$WORK/sherpa-line.txt"
expect "lock: the default lock has the sherpa-onnx line" 0 "sherpa-onnx:2.0.1" cat "$WORK/sherpa-line.txt"
{ cat "$FLOCK"; cat "$WORK/sherpa-line.txt"; } >"$WORK/lock-sherpa.txt"
expect "lock: a fdroid lock with sherpa-onnx is caught" 1 "gradle-fdroid.lockfile" \
  lock_check "$LOCK" "$WORK/lock-sherpa.txt"
expect "lock: a fdroid lock copied from the default one (with sherpa-onnx) is caught" 1 "gradle-fdroid.lockfile" \
  lock_check "$LOCK" "$LOCK"

cp "$LOCK" "$WORK/lock-new.txt"
echo "com.example:added:1.0=releaseRuntimeClasspath" >>"$WORK/lock-new.txt"
expect "lock: a dependency added to the default lock only is caught" 1 "gradle-fdroid.lockfile" \
  lock_check "$WORK/lock-new.txt" "$FLOCK"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) of the F-Droid consistency checks failed." >&2
  exit 1
fi
echo "The F-Droid consistency checks behaved."
