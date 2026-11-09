#!/usr/bin/env bash
# Builds the signed release APKs (one per ABI) with the founder's key, checks them, and prints the
# certificate's SHA-256 for ANDROID_CERT_SHA256 (deploy/personal). Run on the founder's Mac;
# the key lives nowhere else (spec section 8). docs/mobile/release.md has the whole procedure.
#
#   apps/mobile/scripts/release.sh [--tag mobile-vX.Y.Z] [--out <dir>] [--no-clean] [--allow-dirty] [--play]
#
# The signing material comes only from the environment, never from a file in the repo:
#   WAMBITO_KEYSTORE            path of the keystore (.p12 / .jks)
#   WAMBITO_KEY_ALIAS           the key's alias in it
#   WAMBITO_KEYSTORE_PASSWORD   the keystore's password
#   WAMBITO_KEY_PASSWORD        the key's password; left out, the keystore's (PKCS12 keystores have one)
# None of the four is ever printed (tracing is switched off at the first line and the tools get the
# passwords through their environment, not their arguments), and Gradle and Flutter never see them:
# the APKs are built unsigned and signed afterwards with apksigner.
#
# Version: the `mobile-vX.Y.Z` tag at HEAD (or --tag, which must point at HEAD). With no tag it is a
# dev build, 0.0.0-dev.<commit>, below every release (scripts/release-lib.sh). A tagged build needs a
# clean working tree (--allow-dirty to override).
#
# Output: <out>/<versionName>/wambito-<versionName>-<abi>.apk for arm64-v8a and armeabi-v7a, with
# SHA256SUMS and ANDROID_CERT_SHA256.txt. <out> defaults to apps/mobile/dist, which is git-ignored.
# --play also builds the Android App Bundle for Google Play (wambito-<versionName>.aab, versionCode
# base * 10 + 0), signed with jarsigner by the UPLOAD key, never the app key (Play re-signs with the
# app key, which the founder gave Play App Signing once; docs/mobile/play.md). Four more variables:
#   WAMBITO_UPLOAD_KEYSTORE, WAMBITO_UPLOAD_KEY_ALIAS, WAMBITO_UPLOAD_KEYSTORE_PASSWORD and
#   WAMBITO_UPLOAD_KEY_PASSWORD (left out, the upload keystore's password).
# The bundle's manifest is read back with aapt2 for its version and permissions.
#
# Exit codes: 0 done, 1 a check failed, 2 missing input or tool.
set +x
unset BASH_XTRACEFD
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE="$(cd "$HERE/.." && pwd)"
# shellcheck source=release-lib.sh
source "$HERE/release-lib.sh"

ABIS=(arm64-v8a armeabi-v7a)
PACKAGE="com.wambito.app"
SECRET_NAMES=(WAMBITO_KEYSTORE WAMBITO_KEY_ALIAS WAMBITO_KEYSTORE_PASSWORD WAMBITO_KEY_PASSWORD
  WAMBITO_UPLOAD_KEYSTORE WAMBITO_UPLOAD_KEY_ALIAS WAMBITO_UPLOAD_KEYSTORE_PASSWORD WAMBITO_UPLOAD_KEY_PASSWORD)

die() {
  echo "release.sh: $1" >&2
  exit "${2:-1}"
}

# Whatever a signing tool prints, with the four secrets (when they appear) replaced by their names.
redact() {
  awk -v names="${SECRET_NAMES[*]}" '
    BEGIN { n = split(names, list, " ") }
    {
      line = $0
      for (i = 1; i <= n; i++) {
        value = ENVIRON[list[i]]
        while (length(value) > 0 && (at = index(line, value)) > 0) {
          line = substr(line, 1, at - 1) "<" list[i] ">" substr(line, at + length(value))
        }
      }
      print line
    }'
}

# A child process without tracing and without the passwords (only apksigner, jarsigner and keytool get them).
without_secrets() {
  env -u SHELLOPTS -u BASH_ENV -u WAMBITO_KEYSTORE_PASSWORD -u WAMBITO_KEY_PASSWORD -u WAMBITO_KEYSTORE -u WAMBITO_KEY_ALIAS \
    -u WAMBITO_UPLOAD_KEYSTORE_PASSWORD -u WAMBITO_UPLOAD_KEY_PASSWORD -u WAMBITO_UPLOAD_KEYSTORE -u WAMBITO_UPLOAD_KEY_ALIAS "$@"
}
with_secrets() {
  env -u SHELLOPTS -u BASH_ENV "$@"
}

# Runs a command with its output held back, shown only if it fails.
quietly() {
  local log
  log="$(mktemp)"
  if ! "$@" >"$log" 2>&1; then
    cat "$log" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

out_root="$MOBILE/dist"
tag_arg=""
clean=1
allow_dirty=0
play=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) tag_arg="${2:-}"; shift 2 ;;
    --out) out_root="${2:-}"; shift 2 ;;
    --no-clean) clean=0; shift ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --play) play=1; shift ;;
    -h | --help) sed -n '2,/^set +x/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" 2 ;;
  esac
done
[ -n "$out_root" ] || die "--out needs a folder" 2

# --- The signing material (present, not printed) ---------------------------------------------
missing=()
for name in WAMBITO_KEYSTORE WAMBITO_KEY_ALIAS WAMBITO_KEYSTORE_PASSWORD; do
  if [ -z "${!name:-}" ]; then missing+=("$name"); fi
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "release.sh: set ${missing[*]} in your shell first (docs/mobile/release.md, 'The signing key')." >&2
  exit 2
fi
[ -f "$WAMBITO_KEYSTORE" ] && [ -r "$WAMBITO_KEYSTORE" ] || die "the file WAMBITO_KEYSTORE names does not exist or is not readable" 2
export WAMBITO_KEY_PASSWORD="${WAMBITO_KEY_PASSWORD:-$WAMBITO_KEYSTORE_PASSWORD}"
if [ "$play" -eq 1 ]; then
  missing=()
  for name in WAMBITO_UPLOAD_KEYSTORE WAMBITO_UPLOAD_KEY_ALIAS WAMBITO_UPLOAD_KEYSTORE_PASSWORD; do
    if [ -z "${!name:-}" ]; then missing+=("$name"); fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "release.sh: --play needs ${missing[*]} in your shell too (docs/mobile/play.md, 'The upload key')." >&2
    exit 2
  fi
  [ -f "$WAMBITO_UPLOAD_KEYSTORE" ] && [ -r "$WAMBITO_UPLOAD_KEYSTORE" ] ||
    die "the file WAMBITO_UPLOAD_KEYSTORE names does not exist or is not readable" 2
  export WAMBITO_UPLOAD_KEY_PASSWORD="${WAMBITO_UPLOAD_KEY_PASSWORD:-$WAMBITO_UPLOAD_KEYSTORE_PASSWORD}"
fi

# --- Tools -----------------------------------------------------------------------------------------
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$sdk" ] && [ -f "$MOBILE/android/local.properties" ]; then
  sdk="$(sed -n 's/^sdk\.dir=//p' "$MOBILE/android/local.properties")"
fi
build_tools="$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1 || true)"
[ -n "$build_tools" ] || die "no Android build-tools under the SDK ('$sdk'): set ANDROID_HOME (docs/mobile/setup.md)" 2
for tool in apksigner zipalign aapt2; do
  [ -x "$build_tools/$tool" ] || die "$tool is not in $build_tools" 2
done
command -v flutter >/dev/null 2>&1 || die "flutter is not on PATH (docs/mobile/setup.md)" 2

# apksigner is a Java program (17 or newer); the system java may be older, Flutter's configured JDK is not.
java_major() { "$1" -version 2>&1 | sed -n '1s/.*version "\([0-9]*\).*/\1/p'; }
java_bin="${JAVA_HOME:+$JAVA_HOME/bin/java}"
[ -x "${java_bin:-}" ] || java_bin="$(command -v java || true)"
if [ -z "$java_bin" ] || [ "$(java_major "$java_bin")" -lt 17 ] 2>/dev/null; then
  flutter_jdk="$(without_secrets flutter config --machine 2>/dev/null | sed -n 's/.*"jdk-dir": *"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  if [ -n "$flutter_jdk" ] && [ -x "$flutter_jdk/bin/java" ]; then
    java_bin="$flutter_jdk/bin/java"
    export JAVA_HOME="$flutter_jdk"
    export PATH="$flutter_jdk/bin:$PATH"
  fi
fi
[ -n "$java_bin" ] && [ "$(java_major "$java_bin")" -ge 17 ] 2>/dev/null ||
  die "Java 17 or newer is needed for apksigner: set JAVA_HOME (docs/mobile/setup.md)" 2
if [ "$play" -eq 1 ]; then
  # The bundle is signed and read with the same JDK's tools.
  jdk_bin="$(dirname "$java_bin")"
  for tool in jarsigner keytool; do
    [ -x "$jdk_bin/$tool" ] || die "--play needs $tool next to $java_bin (a full JDK 17)" 2
  done
  # Before building anything: the upload key must not be the app key (checked again on the bundle).
  keystore_fingerprint() { # <keystore> <alias> <password variable>
    with_secrets "$jdk_bin/keytool" -list -v -keystore "$1" -alias "$2" -storepass:env "$3" 2>/dev/null |
      sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | head -n 1
  }
  app_key="$(keystore_fingerprint "$WAMBITO_KEYSTORE" "$WAMBITO_KEY_ALIAS" WAMBITO_KEYSTORE_PASSWORD)"
  upload_key="$(keystore_fingerprint "$WAMBITO_UPLOAD_KEYSTORE" "$WAMBITO_UPLOAD_KEY_ALIAS" WAMBITO_UPLOAD_KEYSTORE_PASSWORD)"
  [ -n "$upload_key" ] || die "keytool cannot read the upload key (is the upload alias, or its password, wrong?)" 1
  if [ -n "$app_key" ] && [ "$app_key" = "$upload_key" ]; then
    die "the upload key is the app key, so the bundle would be signed with the app key: use a separate upload key (docs/mobile/play.md)" 1
  fi
fi

# --- The version -------------------------------------------------------------------------------
cd "$MOBILE"
head_commit="$(git rev-parse HEAD)"
short_commit="$(git rev-parse --short=7 HEAD)"
tag=""
if [ -n "$tag_arg" ]; then
  release_is_tag "$tag_arg" || release_version_name "$tag_arg" # prints why it is refused
  [ "$(git rev-parse -q --verify "refs/tags/$tag_arg^{commit}" || true)" = "$head_commit" ] ||
    die "the tag $tag_arg does not exist or does not point at HEAD ($short_commit): check out the tag first" 1
  tag="$tag_arg"
else
  tags_at_head="$(git tag --points-at HEAD --list 'mobile-v*')"
  count="$(printf '%s' "$tags_at_head" | grep -c . || true)"
  if [ "$count" -gt 1 ]; then
    die "HEAD has more than one mobile-v* tag; pass the one to build with --tag:
$tags_at_head" 1
  elif [ "$count" -eq 1 ]; then
    tag="$tags_at_head"
  fi
fi

if [ -n "$tag" ]; then
  version_name="$(release_version_name "$tag")"
  base_code="$(release_base_code "$tag")"
  # F-Droid reads a new tag's version from pubspec.yaml, so the tag must carry the real one.
  release_check_pubspec "$tag" "$MOBILE/pubspec.yaml" || die "fix pubspec.yaml's version at the tag first" 1
  if [ "$allow_dirty" -ne 1 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    die "the working tree has uncommitted changes: a tagged release is built from the tag's commit alone (--allow-dirty to override)" 1
  fi
else
  version_name="$(release_dev_version_name "$short_commit")"
  base_code="$(release_dev_base_code)"
  echo "release.sh: no mobile-v* tag at HEAD: this is a DEV build ($version_name), not a release." >&2
fi

echo "Building Wambito $version_name (base code $base_code) from $short_commit"

# --- Build, unsigned -----------------------------------------------------------------------------
if [ "$clean" -eq 1 ]; then
  quietly without_secrets flutter clean || die "flutter clean failed" 1
fi
quietly without_secrets flutter pub get --enforce-lockfile || die "flutter pub get failed" 1
# sherpa-onnx's AAR (the precise voice model's runtime) comes from a GitHub release, checked against a pinned SHA-256.
without_secrets "$MOBILE/scripts/fetch-sherpa-onnx.sh" || die "could not fetch sherpa-onnx" 1
flutter_out="$MOBILE/build/app/outputs/flutter-apk"
for abi in "${ABIS[@]}"; do rm -f "$flutter_out/app-$abi-release.apk"; done
# WAMBITO_UNSIGNED_RELEASE: android/app/build.gradle.kts leaves the release APK without a signature.
without_secrets env WAMBITO_UNSIGNED_RELEASE=1 flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64 --build-name "$version_name" --build-number "$base_code"

# --- Sign, verify, record ----------------------------------------------------------------------
dist="$out_root/$version_name"
rm -rf "$dist"
mkdir -p "$dist"
fingerprint=""
for abi in "${ABIS[@]}"; do
  unsigned="$flutter_out/app-$abi-release.apk"
  [ -f "$unsigned" ] || die "Flutter did not produce $unsigned" 1
  signed="$dist/wambito-$version_name-$abi.apk"

  # AGP aligns the APK (4 bytes, and 16 KB for the native libraries: Android 15+ phones with 16 KB
  # pages); signing must not move anything, so alignment is checked before and after.
  "$build_tools/zipalign" -c -P 16 4 "$unsigned" || die "$abi: the unsigned APK is not aligned" 1

  signed_ok=1
  with_secrets "$build_tools/apksigner" sign \
    --ks "$WAMBITO_KEYSTORE" --ks-key-alias "$WAMBITO_KEY_ALIAS" \
    --ks-pass env:WAMBITO_KEYSTORE_PASSWORD --key-pass env:WAMBITO_KEY_PASSWORD \
    --min-sdk-version 26 --out "$signed" "$unsigned" 2>&1 | redact ||
    signed_ok=0
  [ "$signed_ok" -eq 1 ] && [ -f "$signed" ] || die "$abi: apksigner did not sign the APK (is the alias, or a password, wrong?)" 1
  rm -f "$signed.idsig"

  "$build_tools/zipalign" -c -P 16 4 "$signed" || die "$abi: the signed APK is not aligned" 1

  report="$(without_secrets "$build_tools/apksigner" verify --verbose --print-certs --min-sdk-version 26 "$signed" 2>&1)" ||
    die "$abi: apksigner does not verify the signed APK:
$(printf '%s\n' "$report" | redact)" 1
  grep -q '^Verified using v2 scheme.*: true' <<<"$report" || die "$abi: the APK has no v2 signature" 1
  if grep -q 'CN=Android Debug' <<<"$report"; then die "$abi: the APK is signed with the debug key" 1; fi
  # Some build-tools print no "Signer … SHA-256 digest" line for --print-certs; keytool reads the
  # same certificate straight from the signed APK, with no secret involved.
  if ! this="$(release_fingerprint_from_apksigner <<<"$report" 2>/dev/null)"; then
    this=""
    if command -v keytool >/dev/null 2>&1; then
      this="$(release_format_fingerprint "$(without_secrets keytool -printcert -jarfile "$signed" 2>/dev/null |
        sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | sort -u)" 2>/dev/null || true)"
    fi
    [ -n "$this" ] || die "$abi: could not read the certificate. apksigner's certificate lines:
$(grep -i -E 'certificate|digest' <<<"$report" || echo '(none)')" 1
  fi
  if [ -z "$fingerprint" ]; then
    fingerprint="$this"
  elif [ "$this" != "$fingerprint" ]; then
    die "$abi: signed with a different certificate than the other APK" 1
  fi

  # What the manifest says, against the scheme in release-lib.sh (build.gradle.kts has its own copy).
  badging="$("$build_tools/aapt2" dump badging "$signed" | sed -n 1p)"
  expected_code="$(if [ -n "$tag" ]; then release_version_code "$tag" "$abi"; else release_dev_version_code "$abi"; fi)"
  case "$badging" in
    "package: name='$PACKAGE' versionCode='$expected_code' versionName='$version_name' "*) ;;
    *) die "$abi: the APK says '$badging', expected versionCode $expected_code and versionName $version_name" 1 ;;
  esac

  if [ -n "$tag" ]; then
    for locale in es-419 es-ES en-US it-IT pt-PT; do
      [ -f "$MOBILE/fastlane/metadata/android/$locale/changelogs/$expected_code.txt" ] ||
        echo "release.sh: no F-Droid changelog for versionCode $expected_code in fastlane/metadata/android/$locale/changelogs" >&2
    done
  fi

  "$HERE/check-permissions.sh" --apk "$signed" >/dev/null || die "$abi: check-permissions.sh refuses the APK (run it for the details)" 1
  echo "Signed and verified: wambito-$version_name-$abi.apk (versionCode $expected_code)"
done

# The same certificate, read from the keystore itself (keytool, when there is one): the APK is
# signed by the key that was named, not by something else that happens to verify.
if command -v keytool >/dev/null 2>&1; then
  listing="$(with_secrets keytool -list -v -keystore "$WAMBITO_KEYSTORE" -alias "$WAMBITO_KEY_ALIAS" \
    -storepass:env WAMBITO_KEYSTORE_PASSWORD 2>&1)" || die "keytool cannot read the key:
$(printf '%s\n' "$listing" | redact)" 1
  from_keystore="$(printf '%s\n' "$listing" | sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | head -n 1)"
  [ "$(release_format_fingerprint "$from_keystore")" = "$fingerprint" ] ||
    die "the APKs' certificate is not the keystore's: keytool and apksigner disagree" 1
else
  echo "release.sh: keytool not found; the certificate was not compared with the keystore's." >&2
fi

release_is_fingerprint "$fingerprint" || die "internal error: '$fingerprint' is not the fingerprint format" 1

# --- The Play bundle (--play) --------------------------------------------------------------------
if [ "$play" -eq 1 ]; then
  bundle_out="$MOBILE/build/app/outputs/bundle/release/app-release.aab"
  rm -f "$bundle_out"
  # Unsigned like the APKs (WAMBITO_UNSIGNED_RELEASE); no split: Play splits the bundle per device.
  without_secrets env WAMBITO_UNSIGNED_RELEASE=1 flutter build appbundle --release \
    --target-platform android-arm,android-arm64 --build-name "$version_name" --build-number "$base_code"
  [ -f "$bundle_out" ] || die "Flutter did not produce $bundle_out" 1
  aab="$dist/$(release_aab_name "$version_name")"

  signed_ok=1
  with_secrets "$jdk_bin/jarsigner" -keystore "$WAMBITO_UPLOAD_KEYSTORE" \
    -storepass:env WAMBITO_UPLOAD_KEYSTORE_PASSWORD -keypass:env WAMBITO_UPLOAD_KEY_PASSWORD \
    -sigalg SHA256withRSA -digestalg SHA-256 -signedjar "$aab" "$bundle_out" "$WAMBITO_UPLOAD_KEY_ALIAS" 2>&1 |
    redact >"$dist/.jarsigner.log" || signed_ok=0
  if [ "$signed_ok" -ne 1 ] || [ ! -f "$aab" ]; then
    cat "$dist/.jarsigner.log" >&2
    rm -f "$dist/.jarsigner.log"
    die "jarsigner did not sign the bundle (is the upload alias, or a password, wrong?)" 1
  fi
  rm -f "$dist/.jarsigner.log"

  verified="$(without_secrets "$jdk_bin/jarsigner" -verify "$aab" 2>&1)" || die "jarsigner does not verify the bundle:
$verified" 1
  grep -q '^jar verified' <<<"$verified" || die "jarsigner does not verify the bundle:
$verified" 1

  # The bundle's certificate is the upload keystore's, and it is not the app key: Play App Signing
  # keeps the two apart, and a leaked upload key can be reset while the app key cannot.
  upload_fingerprint="$(release_format_fingerprint "$(without_secrets "$jdk_bin/keytool" -printcert -jarfile "$aab" 2>/dev/null |
    sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | sort -u)" 2>/dev/null || true)"
  [ -n "$upload_fingerprint" ] || die "could not read the bundle's certificate" 1
  listing="$(with_secrets "$jdk_bin/keytool" -list -v -keystore "$WAMBITO_UPLOAD_KEYSTORE" -alias "$WAMBITO_UPLOAD_KEY_ALIAS" \
    -storepass:env WAMBITO_UPLOAD_KEYSTORE_PASSWORD 2>&1)" || die "keytool cannot read the upload key:
$(printf '%s\n' "$listing" | redact)" 1
  from_upload="$(printf '%s\n' "$listing" | sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | head -n 1)"
  [ "$(release_format_fingerprint "$from_upload")" = "$upload_fingerprint" ] ||
    die "the bundle's certificate is not the upload keystore's" 1
  if [ "$upload_fingerprint" = "$fingerprint" ]; then
    rm -f "$aab"
    die "the bundle is signed with the app key: use a separate upload key (docs/mobile/play.md)" 1
  fi

  # Its manifest, read by aapt2 from the base module (a proto-format APK): the version of the scheme,
  # and the permissions check, as for the APKs.
  base_apk="$(mktemp -d)/base.apk"
  release_aab_base_apk "$aab" "$base_apk" || die "could not read the bundle's base module" 1
  badging="$("$build_tools/aapt2" dump badging "$base_apk" | sed -n 1p)"
  expected_code="$(if [ -n "$tag" ]; then release_version_code "$tag" universal; else release_dev_version_code universal; fi)"
  case "$badging" in
    "package: name='$PACKAGE' versionCode='$expected_code' versionName='$version_name' "*) ;;
    *) die "the bundle says '$badging', expected versionCode $expected_code and versionName $version_name" 1 ;;
  esac
  "$HERE/check-permissions.sh" --apk "$base_apk" >/dev/null || die "check-permissions.sh refuses the bundle (run it on its base module for the details)" 1
  rm -rf "$(dirname "$base_apk")"
  printf '%s\n' "$upload_fingerprint" >"$dist/UPLOAD_CERT_SHA256.txt"
  echo "Signed and verified: $(basename "$aab") (versionCode $expected_code, upload key $upload_fingerprint)"
fi

(
  cd "$dist"
  for file in wambito-*.apk wambito-*.aab; do
    [ -e "$file" ] || continue
    printf '%s  %s\n' "$(release_sha256 "$file")" "$file"
  done >SHA256SUMS
)
printf '%s\n' "$fingerprint" >"$dist/ANDROID_CERT_SHA256.txt"

echo
echo "Done: $dist"
# Only the files this run made (no .aab without --play: a glob that matches nothing fails ls).
(
  cd "$dist"
  built=(wambito-*.apk)
  [ "$play" -eq 0 ] || built+=("$(basename "$aab")")
  ls -l "${built[@]}" | awk '{ print "  " $NF "  " $5 " bytes" }'
)
if [ "$play" -eq 1 ]; then
  echo
  echo "Upload to Play Console (internal testing first): $aab"
fi
echo
echo "Put this in deploy/personal/.env, then run deploy/personal/up.sh:"
echo "ANDROID_CERT_SHA256=$fingerprint"
