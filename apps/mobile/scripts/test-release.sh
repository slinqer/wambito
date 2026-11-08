#!/usr/bin/env bash
# Tests for scripts/release-lib.sh: the version scheme (tag -> versionName, versionCode per ABI) and
# the certificate fingerprint format release.sh prints for ANDROID_CERT_SHA256. No Android SDK, no
# keystore and no build needed; CI runs it in the `mobile` job.
#
#   apps/mobile/scripts/test-release.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-lib.sh
source "$HERE/release-lib.sh"

failures=0
checks=0

# expect <name> <expected> <actual>
expect() {
  checks=$((checks + 1))
  if [ "$2" != "$3" ]; then
    echo "FAIL $1: expected '$2', got '$3'"
    failures=$((failures + 1))
  fi
}
# expect_fail <name> <command...>: the command must exit non-zero
expect_fail() {
  local name="$1"
  shift
  checks=$((checks + 1))
  if "$@" >/dev/null 2>&1; then
    echo "FAIL $name: expected a failure"
    failures=$((failures + 1))
  fi
}

# --- versionName from the tag ------------------------------------------------------------------
expect "name 1.0.0" "1.0.0" "$(release_version_name mobile-v1.0.0)"
expect "name 12.34.56" "12.34.56" "$(release_version_name mobile-v12.34.56)"
expect_fail "no prefix" release_version_name v1.0.0
expect_fail "web tag" release_version_name web-v1.0.0
expect_fail "two parts" release_version_name mobile-v1.0
expect_fail "four parts" release_version_name mobile-v1.0.0.1
expect_fail "pre-release suffix" release_version_name mobile-v1.0.0-rc1
expect_fail "leading zero" release_version_name mobile-v1.01.0
expect_fail "minor over 99" release_version_name mobile-v1.100.0
expect_fail "patch over 99" release_version_name mobile-v1.0.100
expect_fail "major over 9999" release_version_name mobile-v10000.0.0
expect_fail "0.0.0 is the dev version" release_version_name mobile-v0.0.0
expect_fail "0.0.x is below the first release" release_version_name mobile-v0.0.7
expect "0.1.0 is the first release" "0.1.0" "$(release_version_name mobile-v0.1.0)"
expect_fail "empty" release_version_name ""

# --- versionCode: X*10000 + Y*100 + Z, then * 10 + the ABI digit ------------------------------
expect "base 1.0.0" "10000" "$(release_base_code mobile-v1.0.0)"
expect "base 0.1.0" "100" "$(release_base_code mobile-v0.1.0)"
expect "base 1.2.3" "10203" "$(release_base_code mobile-v1.2.3)"
expect "base 9999.99.99" "99999999" "$(release_base_code mobile-v9999.99.99)"

expect "digit universal" "0" "$(release_abi_digit universal)"
expect "digit armeabi-v7a" "1" "$(release_abi_digit armeabi-v7a)"
expect "digit arm64-v8a" "2" "$(release_abi_digit arm64-v8a)"
expect_fail "digit x86_64 is not a target" release_abi_digit x86_64
expect_fail "digit empty" release_abi_digit ""

expect "code 1.0.0 arm32" "100001" "$(release_version_code mobile-v1.0.0 armeabi-v7a)"
expect "code 1.0.0 arm64" "100002" "$(release_version_code mobile-v1.0.0 arm64-v8a)"
expect "code 1.0.0 universal" "100000" "$(release_version_code mobile-v1.0.0 universal)"
expect "code 1.2.3 arm64" "102032" "$(release_version_code mobile-v1.2.3 arm64-v8a)"
# The largest possible code stays below Android's ceiling of 2 100 000 000.
largest="$(release_version_code mobile-v9999.99.99 arm64-v8a)"
expect "largest code" "999999992" "$largest"
checks=$((checks + 1))
if [ "$largest" -ge 2100000000 ]; then
  echo "FAIL ceiling: $largest is over Android's 2100000000"
  failures=$((failures + 1))
fi

# Monotonic: every later release has a higher code than every earlier one, for every ABI, and a
# split of the same release never shares a code with another.
tags=(mobile-v0.1.0 mobile-v0.9.99 mobile-v1.0.0 mobile-v1.0.1 mobile-v1.0.10
  mobile-v1.1.0 mobile-v1.9.99 mobile-v2.0.0 mobile-v10.0.0 mobile-v9999.99.99)
previous_max=0
monotonic="ok"
for tag in "${tags[@]}"; do
  lowest=""
  highest=0
  for abi in universal armeabi-v7a arm64-v8a; do
    code="$(release_version_code "$tag" "$abi")"
    if [ -z "$lowest" ] || [ "$code" -lt "$lowest" ]; then lowest="$code"; fi
    if [ "$code" -gt "$highest" ]; then highest="$code"; fi
  done
  if [ "$lowest" -le "$previous_max" ]; then monotonic="$tag has a code <= an earlier release's ($lowest <= $previous_max)"; fi
  previous_max="$highest"
done
expect "monotonic across releases" "ok" "$monotonic"

# A release always outranks the dev build, whatever the ABI.
# (Flutter ignores --build-number 0, and pubspec.yaml's dev version is +1: the dev base code is 1.)
expect "dev base code" "1" "$(release_dev_base_code)"
expect "dev arm32" "11" "$(release_dev_version_code armeabi-v7a)"
expect "dev arm64" "12" "$(release_dev_version_code arm64-v8a)"
expect "dev name" "0.0.0-dev.abc1234" "$(release_dev_version_name abc1234)"
expect "dev name without a commit" "0.0.0-dev" "$(release_dev_version_name "")"
checks=$((checks + 1))
if [ "$(release_dev_version_code arm64-v8a)" -ge "$(release_version_code mobile-v0.1.0 universal)" ]; then
  echo "FAIL dev build must rank below the first release"
  failures=$((failures + 1))
fi

# --- tag lookup ---------------------------------------------------------------------------------
expect "release tag pattern matches" "yes" "$(release_is_tag mobile-v1.2.3 && echo yes || echo no)"
expect "release tag pattern refuses" "no" "$(release_is_tag mobile-v1.2 && echo yes || echo no)"

# --- the fingerprint ANDROID_CERT_SHA256 expects -------------------------------------------------
# deploy/personal/web-entrypoint.sh keeps a value only if it matches this; the API's
# ANDROID_CERT_SHA256 setting (apps/api/src/config.ts) is as strict. Same expression, kept in step.
web_pattern='^([0-9A-F]{2}:){31}[0-9A-F]{2}$'
lower="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
upper="01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF"
expect "fingerprint from lowercase hex" "$upper" "$(release_format_fingerprint "$lower")"
expect "fingerprint from uppercase hex" "$upper" "$(release_format_fingerprint "$(printf '%s' "$lower" | tr a-f A-F)")"
expect "fingerprint from colon pairs" "$upper" "$(release_format_fingerprint "$upper")"
expect "fingerprint from mixed case colon pairs" "$upper" "$(release_format_fingerprint "$(printf '%s' "$upper" | tr A-F a-f)")"
checks=$((checks + 1))
if ! printf '%s' "$(release_format_fingerprint "$lower")" | grep -Eq "$web_pattern"; then
  echo "FAIL the web container would skip the fingerprint"
  failures=$((failures + 1))
fi
expect_fail "fingerprint too short" release_format_fingerprint "0123456789abcdef"
expect_fail "fingerprint too long" release_format_fingerprint "${lower}00"
expect_fail "fingerprint not hex" release_format_fingerprint "zz23456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
expect_fail "fingerprint empty" release_format_fingerprint ""
expect "is_fingerprint yes" "yes" "$(release_is_fingerprint "$upper" && echo yes || echo no)"
expect "is_fingerprint refuses lowercase" "no" "$(release_is_fingerprint "$lower" && echo yes || echo no)"

# apksigner's `verify --print-certs` text, as recorded from build-tools 36.0.0 (the digest below
# is made up). The signer's certificate digest is read from it.
recorded="$(cat <<TEXT
Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
Number of signers: 1
Signer #1 certificate DN: CN=Test, O=Test
Signer #1 certificate SHA-256 digest: $lower
Signer #1 certificate SHA-1 digest: 0123456789abcdef0123456789abcdef01234567
Signer #1 certificate MD5 digest: 0123456789abcdef0123456789abcdef
Signer #1 key algorithm: RSA
TEXT
)"
expect "digest read from apksigner" "$upper" "$(printf '%s\n' "$recorded" | release_fingerprint_from_apksigner)"
expect "digest read from SDK-ranged signer blocks" "$upper" "$(printf 'Signer (minSdkVersion=26, maxSdkVersion=32) certificate SHA-256 digest: %s\nSigner (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: %s\n' "$lower" "$lower" | release_fingerprint_from_apksigner)"
expect_fail "SDK-ranged blocks with two keys" bash -c "source '$HERE/release-lib.sh'; printf 'Signer (minSdkVersion=26) certificate SHA-256 digest: %s\nSigner (minSdkVersion=33) certificate SHA-256 digest: %s\n' '$lower' 'ab$lower' | release_fingerprint_from_apksigner"
expect_fail "no digest in the output" bash -c "source '$HERE/release-lib.sh'; printf 'DOES NOT VERIFY\n' | release_fingerprint_from_apksigner"
expect_fail "two signers" bash -c "source '$HERE/release-lib.sh'; printf 'Signer #1 certificate SHA-256 digest: %s\nSigner #2 certificate SHA-256 digest: %s\n' '$lower' '$lower' | release_fingerprint_from_apksigner"

# --- pubspec.yaml's version at a release tag: X.Y.Z+<base code> (F-Droid's checkupdates reads it) -
pubspec_dir="$(mktemp -d)"
trap 'rm -rf "$pubspec_dir"' EXIT
pubspec() { printf 'name: wambito\n# a comment\nversion: %s\n\nenvironment:\n' "$1" >"$pubspec_dir/pubspec.yaml"; }
pubspec "1.2.3+10203"
expect "pubspec version read" "1.2.3+10203" "$(release_pubspec_version "$pubspec_dir/pubspec.yaml")"
expect "pubspec version wanted for 1.2.3" "1.2.3+10203" "$(release_pubspec_wanted mobile-v1.2.3)"
release_check_pubspec mobile-v1.2.3 "$pubspec_dir/pubspec.yaml" >/dev/null 2>&1
expect "pubspec matching the tag passes" "0" "$?"
expect_fail "pubspec at the dev version" bash -c "source '$HERE/release-lib.sh'; printf 'version: 0.0.0-dev+1\n' >'$pubspec_dir/dev.yaml'; release_check_pubspec mobile-v1.2.3 '$pubspec_dir/dev.yaml'"
expect_fail "pubspec of another version" bash -c "source '$HERE/release-lib.sh'; printf 'version: 1.2.4+10204\n' >'$pubspec_dir/other.yaml'; release_check_pubspec mobile-v1.2.3 '$pubspec_dir/other.yaml'"
expect_fail "pubspec with the right name, wrong code" bash -c "source '$HERE/release-lib.sh'; printf 'version: 1.2.3+1\n' >'$pubspec_dir/code.yaml'; release_check_pubspec mobile-v1.2.3 '$pubspec_dir/code.yaml'"
expect_fail "pubspec with no version line" bash -c "source '$HERE/release-lib.sh'; printf 'name: wambito\n' >'$pubspec_dir/none.yaml'; release_check_pubspec mobile-v1.2.3 '$pubspec_dir/none.yaml'"
expect "the committed pubspec is at the dev version" "0.0.0-dev+1" "$(release_pubspec_version "$HERE/../pubspec.yaml")"

# --- the Play bundle (release.sh --play) ------------------------------------------------------------
# The AAB takes the scheme's universal digit: base * 10 + 0.
expect "aab name" "wambito-1.0.1.aab" "$(release_aab_name 1.0.1)"
expect "aab name of a dev build" "wambito-0.0.0-dev.abc1234.aab" "$(release_aab_name 0.0.0-dev.abc1234)"
expect_fail "aab name empty" release_aab_name ""
expect "aab code 1.0.1" "100010" "$(release_version_code mobile-v1.0.1 universal)"
# The next release's AAB outranks this release's APKs: someone on the founder's APK moves to Play then.
checks=$((checks + 1))
if [ "$(release_version_code mobile-v1.0.2 universal)" -le "$(release_version_code mobile-v1.0.1 arm64-v8a)" ]; then
  echo "FAIL the next release's AAB must outrank this release's arm64 APK"
  failures=$((failures + 1))
fi

# The bundle's base module as a proto-format APK, which aapt2 reads (badging, permissions) like any APK.
work="$(mktemp -d)"
mkdir -p "$work/aab/base/manifest" "$work/aab/base/dex"
printf 'manifest' >"$work/aab/base/manifest/AndroidManifest.xml"
printf 'table' >"$work/aab/base/resources.pb"
printf 'code' >"$work/aab/base/dex/classes.dex"
(cd "$work/aab" && zip -q -r ../app.aab base)
release_aab_base_apk "$work/app.aab" "$work/base.apk" >/dev/null 2>&1
expect "base apk made" "0" "$?"
expect "base apk entries" "AndroidManifest.xml resources.pb" "$(unzip -Z1 "$work/base.apk" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
expect "base apk manifest is the bundle's" "manifest" "$(unzip -p "$work/base.apk" AndroidManifest.xml 2>/dev/null)"
expect_fail "not a bundle" release_aab_base_apk "$work/base.apk" "$work/other.apk"
rm -rf "$work"

echo "$((checks - failures))/$checks checks passed"
[ "$failures" -eq 0 ]
