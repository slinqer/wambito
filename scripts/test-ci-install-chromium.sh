#!/usr/bin/env bash
# Tests scripts/ci-install-chromium.sh with stub install commands: when the install with system
# packages passes, the browser-only install never runs; when it fails, the browser-only install runs
# and its result is the script's.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
script="${root}/scripts/ci-install-chromium.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# stub <name> <exit code>: a command that records its name in $work/calls and exits with the code.
stub() {
  printf '#!/usr/bin/env bash\necho %s >>"%s/calls"\nexit %s\n' "$1" "$work" "$2" >"$work/$1"
  chmod +x "$work/$1"
}

# run <with-deps exit> <browser-only exit>
run() {
  stub with-deps "$1"
  stub browser-only "$2"
  rm -f "$work/calls"
  WITH_DEPS_CMD="$work/with-deps" BROWSER_ONLY_CMD="$work/browser-only" "$script" >"$work/out" 2>&1
}

calls() { tr '\n' ' ' <"$work/calls"; }

run 0 1 || fail "a passing install with system packages should pass"
[ "$(calls)" = "with-deps " ] || fail "a passing install should not run the browser-only one: $(calls)"

run 1 0 || fail "a failing install with system packages should fall back and pass"
[ "$(calls)" = "with-deps browser-only " ] || fail "a failing install should fall back: $(calls)"
grep -q 'without system packages' "$work/out" || fail "the fallback should say so in the log"

if run 1 1; then fail "both installs failing should fail"; fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "ci-install-chromium: all tests passed"
