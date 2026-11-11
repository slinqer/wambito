#!/bin/sh
# Tests scripts/check-channels.sh against a fixture tree: one Dart file with two channels and a
# helper call, plus Kotlin and Swift files. Each case edits the fixture and says what must happen.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
guard="${root}/scripts/check-channels.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

reset() {
  rm -rf "$work/m"
  mkdir -p "$work/m/lib" "$work/m/android/app/src/main/kotlin/app" "$work/m/ios/Runner"
  cat >"$work/m/lib/feedback.dart" <<'D'
class F {
  static const _a = MethodChannel('wambito/alpha');
  static const _b = MethodChannel('wambito/beta');
  Future<void> one() => _call(_a, 'one', {});
  Future<void> two() => _b.invokeMethod<void>(
    'two',
  );
}
D
  cat >"$work/m/android/app/src/main/kotlin/app/A.kt" <<'K'
val c = "wambito/alpha"
val d = "wambito/beta"
when (call.method) { "one" -> 1; "two" -> 2 }
K
  cat >"$work/m/ios/Runner/A.swift" <<'S'
let c = "wambito/alpha"
let d = "wambito/beta"
switch call.method { case "one": break; case "two": break }
S
  : >"$work/allow.txt"
}

# expect <pass|fail> <name> <text the output must contain, or empty>
expect() {
  want="$1"; name="$2"; needle="$3"
  set +e
  out="$(CHANNEL_ALLOWLIST="$work/allow.txt" sh "$guard" "$work/m" 2>&1)"
  status=$?
  set -e
  if [ "$want" = pass ] && [ "$status" -ne 0 ]; then
    echo "FAIL: ${name} should pass, exited ${status}: ${out}"; failures=$((failures + 1))
  elif [ "$want" = fail ] && [ "$status" -eq 0 ]; then
    echo "FAIL: ${name} should fail, exited 0"; failures=$((failures + 1))
  elif [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -e "$needle"; then
    echo "FAIL: ${name} output lacks '${needle}': ${out}"; failures=$((failures + 1))
  else
    echo "ok: ${name}"
  fi
}

reset
expect pass "both sides have every channel and method" ""

reset
sed 's/case "two": break//' "$work/m/ios/Runner/A.swift" >"$work/x" && mv "$work/x" "$work/m/ios/Runner/A.swift"
expect fail "swift lacks a method" "method two"
expect fail "swift lacks a method (names ios)" "on ios"

reset
sed 's/"two" -> 2//' "$work/m/android/app/src/main/kotlin/app/A.kt" >"$work/x" && mv "$work/x" "$work/m/android/app/src/main/kotlin/app/A.kt"
expect fail "kotlin lacks a method (names android)" "on android"

reset
sed '/beta/d' "$work/m/android/app/src/main/kotlin/app/A.kt" >"$work/x" && mv "$work/x" "$work/m/android/app/src/main/kotlin/app/A.kt"
expect fail "kotlin lacks a channel (names android)" "channel wambito/beta"

reset
rm "$work/m/ios/Runner/A.swift"
printf '%s\n' 'wambito/alpha  # ios-impossible' 'wambito/beta  # ios-part-two' >"$work/allow.txt"
expect pass "allowlisted channels are skipped" ""

reset
printf '%s\n' 'wambito/alpha' >"$work/allow.txt"
expect fail "allowlist line without a reason" "unknown reason"

reset
printf '%s\n' 'wambito/alpha  # because' >"$work/allow.txt"
expect fail "allowlist line with another reason" "unknown reason"

if [ "$failures" -ne 0 ]; then
  echo "test-check-channels: ${failures} failure(s)" >&2
  exit 1
fi
echo "test-check-channels: all passed"
