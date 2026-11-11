#!/usr/bin/env bash
# Checks the install from this machine, without the tunnel: the landing, the app shell, the API
# health, the Android asset links, the MCP's OAuth discovery, that the API schema is blocked at Caddy,
# and that an address outside the allowlist is refused without sending an email.
# Usage: ./smoke.sh [BASE_URL]   (default http://127.0.0.1:$WEB_PORT)
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

base="${1:-http://127.0.0.1:$(cfg WEB_PORT 8088)}"
host="$(cfg PUBLIC_HOSTNAME app.wambito.com)"
failed=0

check() { # NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s (expected %s, got %s)\n' "$1" "$2" "$3"
    failed=1
  fi
}
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

check "GET /                 to the landing" "302 ${LANDING_URL:-https://wambito.com}/" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$base/")"
check "GET /api/health       API" 200 "$(status "$base/api/health")"
check "GET /app              app shell" 200 "$(status "$base/app")"
check "GET /sign-in          app shell" 200 "$(status "$base/sign-in")"
check "GET /nope.png         missing file" 404 "$(status "$base/nope.png")"
# Android App Links: always answered (`[]` until ANDROID_CERT_SHA256 is set), always as JSON.
links="$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$base/.well-known/assetlinks.json")"
check "GET assetlinks.json   200 and JSON" "200 application/json" "${links%%;*}"
# iOS Universal Links: always answered (empty lists until IOS_TEAM_ID is set), always as JSON.
aasa="$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$base/.well-known/apple-app-site-association")"
check "GET apple-app-site-association  200 and JSON" "200 application/json" "${aasa%%;*}"
check "GET /api/v1/me        needs a session" 401 "$(status "$base/api/v1/me")"

# Kept off the internet by Caddy (not in the API): the schema.
check "GET /api/openapi.json  not public" 404 "$(status "$base/api/openapi.json")"

# The MCP, as an assistant finds it: no token is a 401 that points to the resource metadata, which
# names the OAuth server, whose metadata is at the RFC 8414 path.
mcp="$(curl -s -o /dev/null -D - -X POST "$base/mcp" -H 'Content-Type: application/json' -d '{}' | tr -d '\r')"
check "POST /mcp             needs a token" 401 "$(printf '%s\n' "$mcp" | sed -n '1s/^HTTP[^ ]* \([0-9]*\).*/\1/p')"
case "$mcp" in
  *resource_metadata=*) check "                     points to its metadata" yes yes ;;
  *) check "                     points to its metadata" yes no ;;
esac
check "GET protected resource metadata" 200 "$(status "$base/.well-known/oauth-protected-resource/mcp")"
check "GET authorization server metadata" 200 "$(status "$base/.well-known/oauth-authorization-server/api/auth")"
check "GET frame-ancestors    header" "frame-ancestors 'none'" "$(curl -s -I "$base/sign-in" | tr -d '\r' | sed -n "s/^[Cc]ontent-[Ss]ecurity-[Pp]olicy: //p")"

# A made-up address is not on the list. The API answers 403 sign_in_not_allowed and sends nothing.
body="$(curl -s -w '\n%{http_code}' -X POST "$base/api/auth/email-otp/send-verification-otp" \
  -H "Origin: https://$host" -H 'Content-Type: application/json' \
  -d '{"email":"not-on-the-list@example.invalid","type":"sign-in"}')"
check "POST send-code        outside the allowlist" 403 "${body##*$'\n'}"
case "$body" in
  *sign_in_not_allowed*) check "                     error code" sign_in_not_allowed sign_in_not_allowed ;;
  *) check "                     error code" sign_in_not_allowed "(none): $body" ;;
esac

exit "$failed"
