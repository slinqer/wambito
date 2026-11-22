#!/bin/sh
# Tests scripts/check-dockerfile-workspaces.sh against a fixture repository: an app that depends on
# package a, which depends on package b, and the app's Dockerfile.prod. Each case edits the fixture
# and says what must happen.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
guard="${root}/scripts/check-dockerfile-workspaces.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

reset() {
  rm -rf "$work/r"
  mkdir -p "$work/r/apps/app" "$work/r/packages/a" "$work/r/packages/b" "$work/r/packages/c"
  cat >"$work/r/apps/app/package.json" <<'J'
{ "name": "@wambito/app", "dependencies": { "@wambito/a": "workspace:*", "zod": "^4.0.0" } }
J
  cat >"$work/r/packages/a/package.json" <<'J'
{ "name": "@wambito/a", "dependencies": { "@wambito/b": "workspace:*" } }
J
  cat >"$work/r/packages/b/package.json" <<'J'
{ "name": "@wambito/b" }
J
  cat >"$work/r/packages/c/package.json" <<'J'
{ "name": "@wambito/c" }
J
  cat >"$work/r/apps/app/Dockerfile.prod" <<'D'
FROM node:22-alpine AS build
COPY package.json pnpm-lock.yaml ./
COPY packages/a/package.json packages/a/
COPY packages/b/package.json packages/b/
COPY apps/app/package.json apps/app/
RUN pnpm install --frozen-lockfile --filter "@wambito/app..."
COPY packages/a packages/a
COPY packages/b packages/b
COPY apps/app apps/app
D
}

# expect <pass|fail> <name> <text the output must contain, or empty>
expect() {
  want="$1"; name="$2"; needle="$3"
  set +e
  out="$(sh "$guard" "$work/r" apps/app 2>&1)"
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

edit() {
  sed "$1" "$work/r/apps/app/Dockerfile.prod" >"$work/x" && mv "$work/x" "$work/r/apps/app/Dockerfile.prod"
}

reset
expect pass "every workspace dependency is copied" ""

reset
edit '/packages\/b\/package.json/d'
expect fail "a transitive dependency's package.json is missing" "packages/b/package.json"

reset
edit '/^COPY packages\/a packages\/a$/d'
expect fail "a direct dependency's sources are missing" "sources of packages/a"

reset
edit '/^COPY packages\/[ab] packages\/[ab]$/d'
printf '%s\n' 'COPY packages packages' >>"$work/r/apps/app/Dockerfile.prod"
expect pass "copying the whole packages folder counts as the sources" ""

reset
cat >"$work/r/apps/app/package.json" <<'J'
{ "name": "@wambito/app", "devDependencies": { "@wambito/c": "workspace:*" },
  "dependencies": { "@wambito/a": "workspace:*" } }
J
expect fail "a dev dependency counts too (the install filter installs it)" "packages/c/package.json"

reset
rm "$work/r/apps/app/Dockerfile.prod"
expect fail "no Dockerfile.prod" "Dockerfile.prod"

if [ "$failures" -ne 0 ]; then
  echo "test-check-dockerfile-workspaces: ${failures} failure(s)" >&2
  exit 1
fi
echo "test-check-dockerfile-workspaces: all passed"
