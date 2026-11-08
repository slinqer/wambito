#!/usr/bin/env bash
# Fails when fdroid/com.wambito.app.yml has drifted from what the repo builds with. Once the recipe
# is merged into fdroiddata, its copy there is the live one and AutoUpdateMode only bumps versions
# and commits, so a change here that the recipe does not follow breaks (or mis-builds) the next
# F-Droid release; docs/mobile/fdroid.md, "Changing the recipe after F-Droid publishes". Checks,
# in every build entry:
#   - the srclib flutter@<version> equals .flutter-version;
#   - each srclib revision (vosk-api, kaldi, openfst, OpenBLAS, clapack) equals the *_REV pinned in
#     scripts/build-native-deps.sh, and jna@<tag> equals JNA_VERSION without "-src";
#   - ndk: is the NDK release build-native-deps.sh names in its NDK_VERSION line's comment (the app's
#     own NDK is flutter.ndkVersion, set by the Flutter SDK and not readable without it), and
#     scripts/build-sherpa-onnx.sh's NDK_VERSION is the same;
# and, for the precise voice model (sherpa-onnx from source, arm64-v8a only):
#   - the arm64-v8a entry lists every source pinned in build-sherpa-onnx.sh ("pin <name> <commit>")
#     as <name>@<commit>, runs build-sherpa-onnx.sh and builds with -P wambito.preciseFromSource=true;
#     the armeabi-v7a entry does none of it;
#   - every one of those sources has fdroid/srclibs/<name>.yml naming its git URL, except the ones
#     fdroiddata already has (FDROIDDATA_SRCLIBS below), which the merge request reuses.
# Text only, so it runs anywhere in a second. The files can be named for tests.
#
# Usage, from anywhere: apps/mobile/scripts/check-fdroid-recipe.sh
# Exit codes: 0 they agree, 1 they differ.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE="$(cd "$DIR/.." && pwd)"
RECIPE="${RECIPE:-$MOBILE/fdroid/com.wambito.app.yml}"
DEPS="${DEPS:-$DIR/build-native-deps.sh}"
FLUTTER_VERSION_FILE="${FLUTTER_VERSION_FILE:-$MOBILE/.flutter-version}"
SHERPA="${SHERPA:-$DIR/build-sherpa-onnx.sh}"
SRCLIBS="${SRCLIBS:-$MOBILE/fdroid/srclibs}"
# fdroiddata's own srclibs with the same repository (checked when this was written): reused as
# they are, so the repo has no file of its own for them.
FDROIDDATA_SRCLIBS=" onnxruntime abseil-cpp cpuinfo "
failures=0
problem() {
  echo "$1" >&2
  failures=$((failures + 1))
}

entries="$(grep -c '^  - versionName:' "$RECIPE")"
[ "$entries" -gt 0 ] || problem "$RECIPE has no build entries."

# srclib_refs <name>: the ref of every "- <name>@<ref>" line, one per line.
srclib_refs() { sed -n "s/^      - $1@\\([^[:space:]]*\\)\$/\\1/p" "$RECIPE"; }
# expect_srclib <name> <wanted ref> <where the wanted ref comes from>
expect_srclib() {
  local name="$1" want="$2" source="$3" refs count bad
  refs="$(srclib_refs "$name")"
  count="$(grep -c . <<<"$refs")"
  bad="$(grep -vxF -- "$want" <<<"$refs" || true)"
  if [ -z "$want" ]; then
    problem "recipe: could not read $name's pinned revision from $source."
  elif [ "$count" -ne "$entries" ] || [ -n "$bad" ]; then
    problem "recipe: $name@... must be $name@$want ($source) in all $entries build entries; found: $(tr '\n' ' ' <<<"$refs")"
  fi
}
dep_value() { sed -n "s/^$1=\\([^[:space:]]*\\).*/\\1/p" "$DEPS"; }

expect_srclib flutter "$(tr -d '[:space:]' <"$FLUTTER_VERSION_FILE")" ".flutter-version"
expect_srclib vosk-api "$(dep_value VOSK_REV)" "VOSK_REV in build-native-deps.sh"
expect_srclib kaldi "$(dep_value KALDI_REV)" "KALDI_REV in build-native-deps.sh"
expect_srclib openfst "$(dep_value OPENFST_REV)" "OPENFST_REV in build-native-deps.sh"
expect_srclib OpenBLAS "$(dep_value OPENBLAS_REV)" "OPENBLAS_REV in build-native-deps.sh"
expect_srclib clapack "$(dep_value CLAPACK_REV)" "CLAPACK_REV in build-native-deps.sh"
expect_srclib jna "$(dep_value JNA_VERSION | sed 's/-src$//')" "JNA_VERSION in build-native-deps.sh"

# The NDK: "NDK_VERSION=28.2.13676358   # r28c, ..." names the release in its comment.
ndk_release="$(sed -n 's/^NDK_VERSION=[^#]*# *\(r[0-9][0-9a-z]*\).*/\1/p' "$DEPS")"
ndks="$(sed -n 's/^    ndk: \(.*\)$/\1/p' "$RECIPE")"
if [ -z "$ndk_release" ]; then
  problem "recipe: could not read the NDK release from NDK_VERSION's comment in build-native-deps.sh."
elif [ "$(grep -c . <<<"$ndks")" -ne "$entries" ] || [ -n "$(grep -vxF -- "$ndk_release" <<<"$ndks" || true)" ]; then
  problem "recipe: ndk must be $ndk_release (NDK_VERSION in build-native-deps.sh) in all $entries build entries; found: $(tr '\n' ' ' <<<"$ndks")"
fi

sherpa_ndk="$(sed -n 's/^NDK_VERSION=\([^[:space:]]*\).*/\1/p' "$SHERPA")"
[ -n "$sherpa_ndk" ] && [ "$sherpa_ndk" = "$(dep_value NDK_VERSION)" ] ||
  problem "build-sherpa-onnx.sh's NDK_VERSION ($sherpa_ndk) is not build-native-deps.sh's ($(dep_value NDK_VERSION))."

# entry <abi>: the build entry whose output is the <abi> APK, as text.
entry() {
  awk -v abi="$1" '/^  - versionName:/ { if (text ~ "app-" abi "-release.apk") print text; text = "" }
    /^[A-Za-z]/ { if (text ~ "app-" abi "-release.apk") print text; text = ""; next }
    { text = text $0 "\n" } END { if (text ~ "app-" abi "-release.apk") print text }' "$RECIPE" | sed 's/\\n/\n/g'
}
arm64="$(entry arm64-v8a)"
v7a="$(entry armeabi-v7a)"
[ -n "$arm64" ] || problem "recipe: no build entry for app-arm64-v8a-release.apk."
[ -n "$v7a" ] || problem "recipe: no build entry for app-armeabi-v7a-release.apk."
pins="$(sed -n 's/^pin \([^[:space:]]*\) \([0-9a-f]\{40\}\) \([^[:space:]]*\) .*/\1 \2 \3/p' "$SHERPA")"
[ "$(grep -c . <<<"$pins")" -ge 2 ] || problem "could not read the pinned sources of build-sherpa-onnx.sh."
while read -r name rev url; do
  [ -n "$name" ] || continue
  grep -qxF -- "      - $name@$rev" <<<"$arm64" ||
    problem "recipe: the arm64-v8a entry must list $name@$rev (build-sherpa-onnx.sh)."
  ! grep -q -- "^      - $name@" <<<"$v7a" ||
    problem "recipe: the armeabi-v7a entry must not list $name (the precise model is arm64-v8a only)."
  case "$FDROIDDATA_SRCLIBS" in *" $name "*) continue ;; esac
  if [ ! -f "$SRCLIBS/$name.yml" ]; then
    problem "srclibs: no $name.yml for $name ($url)."
  elif ! grep -qxF "Repo: $url.git" "$SRCLIBS/$name.yml"; then
    problem "srclibs: $name.yml must say Repo: $url.git"
  fi
done <<<"$pins"
grep -q 'scripts/build-sherpa-onnx.sh' <<<"$arm64" ||
  problem "recipe: the arm64-v8a entry must run scripts/build-sherpa-onnx.sh."
grep -q -- '-P wambito.preciseFromSource=true' <<<"$arm64" ||
  problem "recipe: the arm64-v8a entry must build with -P wambito.preciseFromSource=true."
! grep -q -e 'build-sherpa-onnx' -e 'wambito.preciseFromSource' <<<"$v7a" ||
  problem "recipe: the armeabi-v7a entry must not build the precise model."

if [ "$failures" -gt 0 ]; then
  echo "The F-Droid recipe has drifted from the repo: fix it here, and open the same change as a merge request on fdroiddata before tagging." >&2
  exit 1
fi
echo "The F-Droid recipe agrees with .flutter-version, build-native-deps.sh and build-sherpa-onnx.sh in all $entries build entries."
