#!/usr/bin/env bash
# Tests scripts/ci-install-chromium.sh with a stub install command and a temporary mirror list:
# a first success touches nothing; a failure swaps the runner's apt mirror for the main archive and
# retries; a command that always fails ends in failure after the attempts.
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

# A stub that fails the first $1 calls, then succeeds; it counts calls in $work/calls.
stub() {
  cat >"$work/install" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$work/calls" 2>/dev/null || echo 0) + 1 ))
echo "\$n" >"$work/calls"
[ "\$n" -gt $1 ]
EOF
  chmod +x "$work/install"
  rm -f "$work/calls"
  printf 'http://azure.archive.ubuntu.com/ubuntu/\tpriority:1\n' >"$work/mirrors"
}

run() {
  APT_MIRRORS_FILE="$work/mirrors" INSTALL_CMD="$work/install" SUDO="" RETRY_SLEEP=0 \
    "$script" >"$work/out" 2>&1
}

# 1. Success first time: one call, mirror list untouched.
stub 0
run || fail "first-time success should pass"
[ "$(cat "$work/calls")" = 1 ] || fail "first-time success should call once"
grep -q azure "$work/mirrors" || fail "first-time success should keep the mirror list"

# 2. One failure: the mirror list becomes the main archive and the retry passes.
stub 1
run || fail "a failure then success should pass"
[ "$(cat "$work/calls")" = 2 ] || fail "a failure then success should call twice"
grep -q azure "$work/mirrors" && fail "a failure should drop the runner's mirror"
grep -q 'http://archive.ubuntu.com/ubuntu/' "$work/mirrors" ||
  fail "a failure should switch to the main archive"

# 3. Always failing: fails after 3 attempts.
stub 99
if run; then fail "an always-failing install should fail"; fi
[ "$(cat "$work/calls")" = 3 ] || fail "an always-failing install should try 3 times"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "ci-install-chromium: all tests passed"
