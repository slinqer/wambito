#!/usr/bin/env bash
# Tests gen-mcp-keys.sh: it prints a fresh X25519 key pair as the two .env lines the install needs,
# MCP_WK_PUBLIC_KEY (no private part) and MCP_WK_PRIVATE_KEY, each a JWK as a JSON string; the two
# halves belong together (the same x); and two runs give two different pairs. Needs node, and the
# repository's dependencies installed (pnpm install). Run: ./test-mcp-keys.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0
ok() { printf 'ok    %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}
# check NAME EXPECTED ACTUAL
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

first="$("$here/gen-mcp-keys.sh")"
second="$("$here/gen-mcp-keys.sh")"

check "prints two lines" "2" "$(printf '%s\n' "$first" | wc -l | tr -d ' ')"
check "the first line is the public key" "MCP_WK_PUBLIC_KEY" "$(printf '%s\n' "$first" | sed -n 1p | cut -d= -f1)"
check "the second line is the private key" "MCP_WK_PRIVATE_KEY" "$(printf '%s\n' "$first" | sed -n 2p | cut -d= -f1)"

# value LINE: the JSON between the single quotes after the first =.
value() { printf '%s' "$1" | cut -d= -f2- | sed "s/^'//; s/'\$//"; }
pub="$(value "$(printf '%s\n' "$first" | sed -n 1p)")"
priv="$(value "$(printf '%s\n' "$first" | sed -n 2p)")"

# field JSON KEY: a member of the JSON object, empty when missing.
field() { node -e 'const j = JSON.parse(process.argv[1]); process.stdout.write(String(j[process.argv[2]] ?? ""))' "$1" "$2"; }

check "the public key is an X25519 OKP" "OKP X25519" "$(field "$pub" kty) $(field "$pub" crv)"
check "the public key has no private part" "" "$(field "$pub" d)"
check "the private key is an X25519 OKP" "OKP X25519" "$(field "$priv" kty) $(field "$priv" crv)"
[ -n "$(field "$priv" d)" ] && ok "the private key has d" || fail "the private key has d"
check "the two halves match" "$(field "$pub" x)" "$(field "$priv" x)"
check "the x is 43 characters (32 bytes)" "43" "$(field "$pub" x | tr -d '\n' | wc -c | tr -d ' ')"
[ "$first" != "$second" ] && ok "two runs give two pairs" || fail "two runs give two pairs"

[ "$failures" -eq 0 ] || {
  printf '%d failed\n' "$failures" >&2
  exit 1
}
echo "all ok"
