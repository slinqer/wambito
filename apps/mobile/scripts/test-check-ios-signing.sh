#!/usr/bin/env bash
# Tests check-ios-signing.sh against a fixture iOS folder in a scratch git repo:
#   - no DEVELOPMENT_TEAM line, or only DEVELOPMENT_TEAM = ""; passes (exit 0);
#   - DEVELOPMENT_TEAM = ABCDE12345; (also quoted, or with an [sdk=...] condition) fails (exit 1) and names project.pbxproj;
#   - a tracked ios/Flutter/Signing.xcconfig fails (exit 1) and names the file.
#
# Usage, from anywhere: apps/mobile/scripts/test-check-ios-signing.sh
# Exit codes: 0 every check passed, 1 a check failed.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$DIR/check-ios-signing.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "ok    $1"; }
fail() {
  echo "FAIL  $1" >&2
  failures=$((failures + 1))
}

git -C "$WORK" init -q
IOS="$WORK/ios"
mkdir -p "$IOS/Runner.xcodeproj" "$IOS/Flutter"
PBX="$IOS/Runner.xcodeproj/project.pbxproj"

# expect <name> <exit code> <text the output must contain, or empty>
expect() {
  local name="$1" want="$2" needle="$3" out code
  out="$("$GUARD" "$IOS" 2>&1)"
  code=$?
  if [ "$code" -ne "$want" ]; then
    fail "$name (exit $code, wanted $want): $out"
  elif [ -n "$needle" ] && ! printf '%s' "$out" | grep -q "$needle"; then
    fail "$name (message lacks '$needle'): $out"
  else
    pass "$name"
  fi
}

printf 'buildSettings = {\n\tPRODUCT_NAME = Runner;\n};\n' >"$PBX"
expect "no team line passes" 0 ""

printf 'buildSettings = {\n\tDEVELOPMENT_TEAM = "";\n};\n' >"$PBX"
expect "empty team passes" 0 ""

printf 'buildSettings = {\n\tDEVELOPMENT_TEAM = ABCDE12345;\n};\n' >"$PBX"
expect "a team id fails" 1 "project.pbxproj"

printf 'buildSettings = {\n\tDEVELOPMENT_TEAM = "ABCDE12345";\n};\n' >"$PBX"
expect "a quoted team id fails" 1 "project.pbxproj"

printf 'buildSettings = {\n\t"DEVELOPMENT_TEAM[sdk=iphoneos*]" = ABCDE12345;\n};\n' >"$PBX"
expect "an sdk-conditional team id fails" 1 "project.pbxproj"

printf 'buildSettings = {\n\tDEVELOPMENT_TEAM[sdk=iphoneos*] = "ABCDE12345";\n};\n' >"$PBX"
expect "an unquoted-key conditional quoted id fails" 1 "project.pbxproj"

printf 'buildSettings = {\n\tPRODUCT_NAME = Runner;\n};\n' >"$PBX"
printf 'DEVELOPMENT_TEAM = ABCDE12345\n' >"$IOS/Flutter/Signing.xcconfig"
expect "untracked Signing.xcconfig passes" 0 ""

git -C "$WORK" add -f ios/Flutter/Signing.xcconfig
expect "tracked Signing.xcconfig fails" 1 "Signing.xcconfig"

[ "$failures" -eq 0 ] || exit 1
echo "all checks passed"
