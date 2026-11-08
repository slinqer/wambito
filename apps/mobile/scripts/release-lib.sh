# Sourced by release.sh, check-reproducible.sh and test-release.sh; defines functions, runs nothing.
# Works with the bash 3.2 that macOS ships.
#
# The version scheme (docs/mobile/release.md):
#   versionName  X.Y.Z from the tag `mobile-vX.Y.Z`
#   base code    X*10000 + Y*100 + Z          (X up to 9999, Y and Z up to 99; from 0.1.0)
#   versionCode  base code * 10 + ABI digit   (0 universal, 1 armeabi-v7a, 2 arm64-v8a)
# so each release is above the one before, and the two split APKs of a release differ. The same
# arithmetic is in android/app/build.gradle.kts (the APK's real code); release.sh checks the APKs
# it built against this one.

RELEASE_TAG_PATTERN='^mobile-v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$'

# release_is_tag <tag>: succeeds for `mobile-vX.Y.Z` from 0.1.0 up (0.0.x is the dev builds' range).
release_is_tag() {
  [[ "${1:-}" =~ $RELEASE_TAG_PATTERN ]] || return 1
  [ $((BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3])) -ge 100 ]
}

# release_version_name <tag>: X.Y.Z, or an error.
release_version_name() {
  if ! release_is_tag "${1:-}"; then
    echo "Not a release tag (mobile-vX.Y.Z from 0.1.0, X up to 9999, Y and Z up to 99): '${1:-}'" >&2
    return 1
  fi
  [[ "$1" =~ $RELEASE_TAG_PATTERN ]]
  echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
}

# release_base_code <tag>: X*10000 + Y*100 + Z.
release_base_code() {
  release_is_tag "${1:-}" || { release_version_name "${1:-}" >/dev/null; return 1; }
  [[ "$1" =~ $RELEASE_TAG_PATTERN ]]
  echo $((BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3]))
}

# release_abi_digit <abi>: the last digit of a split APK's versionCode.
release_abi_digit() {
  case "${1:-}" in
    universal) echo 0 ;;
    armeabi-v7a) echo 1 ;;
    arm64-v8a) echo 2 ;;
    *) echo "No version digit for ABI '${1:-}' (armeabi-v7a, arm64-v8a or universal)" >&2; return 1 ;;
  esac
}

# release_version_code <tag> <abi>
release_version_code() {
  local base digit
  base="$(release_base_code "${1:-}")" || return 1
  digit="$(release_abi_digit "${2:-}")" || return 1
  echo $((base * 10 + digit))
}

# pubspec.yaml's `version:` at a release tag is X.Y.Z+<base code> (the main branch keeps the dev
# value): F-Droid's checkupdates reads the version of a new mobile-v* tag from it (UpdateCheckData in
# fdroid/com.wambito.app.yml), and release.sh refuses a tag whose pubspec says something else.

# release_pubspec_version <pubspec.yaml>: the value of its top-level `version:` line, or nothing.
release_pubspec_version() {
  sed -n 's/^version:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "${1:-}" 2>/dev/null | head -n 1
}

# release_pubspec_wanted <tag>: the `version:` a pubspec must carry at that tag, X.Y.Z+<base code>.
release_pubspec_wanted() {
  local name base
  name="$(release_version_name "${1:-}")" || return 1
  base="$(release_base_code "$1")" || return 1
  echo "$name+$base"
}

# release_check_pubspec <tag> <pubspec.yaml>: succeeds when the pubspec's version is the tag's.
release_check_pubspec() {
  local want have
  want="$(release_pubspec_wanted "${1:-}")" || return 1
  have="$(release_pubspec_version "${2:-}")"
  if [ "$have" != "$want" ]; then
    echo "pubspec.yaml says version '${have:-(none)}', but the tag ${1} needs 'version: $want' (docs/mobile/release.md)" >&2
    return 1
  fi
}

# The version of a build with no release tag: below every release (base code 1, as pubspec.yaml's
# 0.0.0-dev+1, so 11 and 12 for the two splits, where the first release, 0.1.0, is 1000), and
# plainly a dev build in the name. (Flutter ignores --build-number 0, hence 1 and not 0.)
release_dev_base_code() { echo 1; }
release_dev_version_name() { echo "0.0.0-dev${1:+.$1}"; }
release_dev_version_code() {
  local digit
  digit="$(release_abi_digit "${1:-}")" || return 1
  echo $(($(release_dev_base_code) * 10 + digit))
}

# release_is_fingerprint <text>: the shape ANDROID_CERT_SHA256 takes. This is the check
# deploy/personal/web-entrypoint.sh applies (and the API's config is as strict): uppercase hex
# pairs, colons between them, 32 pairs.
release_is_fingerprint() {
  printf '%s' "${1:-}" | grep -Eq '^([0-9A-F]{2}:){31}[0-9A-F]{2}$'
}

# release_format_fingerprint <hex>: 64 hex digits (or 32 colon pairs), any case, as AB:CD:...:EF.
release_format_fingerprint() {
  local hex formatted
  hex="$(printf '%s' "${1:-}" | tr -d ':' | tr 'a-f' 'A-F')"
  if ! printf '%s' "$hex" | grep -Eq '^[0-9A-F]{64}$'; then
    echo "Not a SHA-256 digest (64 hex digits): '${1:-}'" >&2
    return 1
  fi
  formatted="$(printf '%s' "$hex" | sed -E 's/(..)/\1:/g; s/:$//')"
  release_is_fingerprint "$formatted" || return 1
  echo "$formatted"
}

# release_fingerprint_from_apksigner: reads `apksigner verify --print-certs` output on stdin and
# prints the signing certificate's SHA-256 as AB:CD:...:EF. One signer only: an APK with two would
# need a decision, not a guess.
release_fingerprint_from_apksigner() {
  local digests count
  local report numbered
  report="$(cat)"
  # Newer apksigner prints SDK-ranged blocks of the same signer as "Signer (minSdkVersion=…, …)";
  # older ones print "Signer #1". Two numbered signers are two keys; ranged blocks of one key are not.
  numbered="$(printf '%s\n' "$report" | grep -c '^Signer #[0-9][0-9]* certificate SHA-256 digest:' || true)"
  digests="$(printf '%s\n' "$report" | sed -n 's/^Signer[^:]* certificate SHA-256 digest: *//p' | sort -u)"
  count="$(printf '%s' "$digests" | grep -c . || true)"
  if [ "$numbered" -gt 1 ] || [ "$count" -ne 1 ]; then
    echo "Expected one signer's SHA-256 digest from apksigner, found $count" >&2
    return 1
  fi
  release_format_fingerprint "$digests"
}

# release_sha256 <file>: the SHA-256 of a file, on macOS (shasum) and Linux (sha256sum).
release_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# --- The Play bundle (release.sh --play, docs/mobile/release.md "The Play bundle") ---------------
# The AAB takes the universal digit: base * 10 + 0, below the same release's split APKs and above
# every earlier release's.

# release_aab_name <versionName>: the signed bundle's file name.
release_aab_name() {
  [ -n "${1:-}" ] || { echo "release_aab_name needs a versionName" >&2; return 1; }
  echo "wambito-$1.aab"
}

# release_aab_base_apk <aab> <out.apk>: the bundle's base manifest and resource table, at the root of
# a zip: a proto-format APK, which `aapt2 dump badging|permissions` read like any APK (no bundletool).
release_aab_base_apk() {
  local work
  work="$(mktemp -d)"
  if ! unzip -q -o "${1:-}" base/manifest/AndroidManifest.xml base/resources.pb -d "$work" 2>/dev/null; then
    rm -rf "$work"
    echo "not an app bundle (no base/manifest/AndroidManifest.xml and base/resources.pb): ${1:-}" >&2
    return 1
  fi
  rm -f "${2:-}"
  mv "$work/base/manifest/AndroidManifest.xml" "$work/base/resources.pb" "$work/"
  local ok=0
  (cd "$work" && zip -q -X base.apk AndroidManifest.xml resources.pb) && mv "$work/base.apk" "${2:-}" || ok=1
  rm -rf "$work"
  return "$ok"
}
