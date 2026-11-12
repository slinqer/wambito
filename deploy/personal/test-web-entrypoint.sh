#!/usr/bin/env bash
# Tests web-entrypoint.sh: the two files it writes under /.well-known before it starts Caddy,
# assetlinks.json (ANDROID_CERT_SHA256) and apple-app-site-association (IOS_TEAM_ID). Runs the
# script on this machine with `true` as the command to exec and a temporary folder for the files
# (WELL_KNOWN_DIR) and templates (TEMPLATE_DIR): no Docker, no .env. Run: ./test-web-entrypoint.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

ok() { printf 'ok    %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}
# check NAME WANT GOT
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

EMPTY_AASA='{"applinks":{"details":[]},"webcredentials":{"apps":[]}}'
APP_ID='"ABCDE12345.com.wambito.app"'
FILLED_AASA='{"applinks":{"details":[{"appIDs":['$APP_ID'],"components":[{"/":"/auth/verify"}]}]},"webcredentials":{"apps":['$APP_ID']}}'

# run_entrypoint NAME [VAR=VALUE...]: runs the entrypoint with only those variables set, in a fresh
# folder; leaves the folder in $tmp/NAME/wk and the warnings in $tmp/NAME/err.
run_entrypoint() {
  local name="$1"
  shift
  mkdir -p "$tmp/$name"
  env -u ANDROID_CERT_SHA256 -u IOS_TEAM_ID "$@" \
    WELL_KNOWN_DIR="$tmp/$name/wk" TEMPLATE_DIR="$here" \
    sh "$here/web-entrypoint.sh" true 2>"$tmp/$name/err"
}
# aasa NAME: the AASA file the run left, compacted, after checking it is valid JSON.
aasa() {
  local file="$tmp/$1/wk/apple-app-site-association"
  python3 -m json.tool "$file" >/dev/null || fail "$1: the AASA file is not valid JSON"
  tr -d '\n' <"$file"
}

run_entrypoint empty
check "empty: no IOS_TEAM_ID, empty lists" "$EMPTY_AASA" "$(aasa empty)"
check "empty: no warning" "" "$(cat "$tmp/empty/err")"

run_entrypoint blank IOS_TEAM_ID=
check "blank: empty IOS_TEAM_ID, empty lists" "$EMPTY_AASA" "$(aasa blank)"

run_entrypoint valid IOS_TEAM_ID=ABCDE12345
check "valid: both lists hold the app id" "$FILLED_AASA" "$(aasa valid)"
check "valid: no warning" "" "$(cat "$tmp/valid/err")"

run_entrypoint malformed IOS_TEAM_ID=abc
check "malformed: empty lists" "$EMPTY_AASA" "$(aasa malformed)"
check "malformed: warning" "web: IOS_TEAM_ID is not a 10-character team id; skipped" \
  "$(cat "$tmp/malformed/err")"

run_entrypoint spaces "IOS_TEAM_ID= ABCDE12345 "
check "spaces: trimmed" "$FILLED_AASA" "$(aasa spaces)"

# The Android file is unchanged.
check "assetlinks: unset is []" "[]" "$(tr -d '\n' <"$tmp/empty/wk/assetlinks.json")"
fp="$(printf 'AA:%.0s' $(seq 1 31))AA"
run_entrypoint android "ANDROID_CERT_SHA256=$fp"
case "$(cat "$tmp/android/wk/assetlinks.json")" in
  *"\"$fp\""*) ok "assetlinks: a fingerprint is written" ;;
  *) fail "assetlinks: a fingerprint is written" ;;
esac

if [ "$failures" -gt 0 ]; then
  printf '\n%s check(s) failed\n' "$failures"
  exit 1
fi
printf '\nall checks passed\n'
