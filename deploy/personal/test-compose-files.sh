#!/usr/bin/env bash
# Tests how the personal install picks its way of being reached, from COMPOSE_FILE in .env: unset is
# the tunnel (today's way), docker-compose.yml:docker-compose.direct.yml is the direct way (a server
# with its own public address). Reads the compose files with `docker compose config`, which needs
# the docker CLI but no running daemon. Each case has its own temporary .env (ENV_FILE). Needs jq.
# Run: ./test-compose-files.sh
#
# What it checks: which files lib.sh hands to docker compose, and that it refuses any other file;
# what web publishes in each way (direct: 80, 443 and 443/udp to the world, the plain-HTTP listener
# on 127.0.0.1 only; tunnel: 127.0.0.1 only, as before); which Caddy config web runs; which services
# up.sh starts (cloudflared only in the tunnel way, and not with --no-tunnel); that a bare
# `docker compose up` in the direct way has no cloudflared either; the commands restore.sh prints;
# the names of the stack (project, volume, images) and the role and database the API connects to.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Settings from the shell would win over the test's .env (as they do for docker compose).
unset COMPOSE_FILE COMPOSE_PROFILES WEB_PORT PUBLIC_HOSTNAME NETWORK_PREFIX TUNNEL_ID
# shellcheck source=lib.sh
. "$here/lib.sh"

command -v jq >/dev/null 2>&1 || die "jq is not installed"
command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
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

# with_env NAME [LINE...]: a fresh .env for one case, with the values compose requires, plus LINEs.
with_env() {
  local name="$1"
  shift
  ENV_FILE="$tmp/$name.env"
  {
    printf '%s\n' POSTGRES_PASSWORD=test APP_DB_PASSWORD=test BETTER_AUTH_SECRET=test \
      SIGN_IN_ALLOWLIST=you@example.com
    if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; fi
  } >"$ENV_FILE"
}

# web_ports: what web publishes, one "HOST_IP:PUBLISHED->TARGET/PROTOCOL" per line, sorted.
web_ports() {
  compose config --format json |
    jq -r '.services.web.ports[] | "\(.host_ip // "" | if . == "" then "" else . + ":" end)\(.published)->\(.target)/\(.protocol)"' |
    sort
}
web_json() { compose config --format json | jq -r ".services.web$1"; }

# --- tunnel: COMPOSE_FILE unset. ------------------------------------------------------------------
with_env unset
check "unset: tunnel" tunnel "$(exposure)"
check "unset: only docker-compose.yml" "$DIR/docker-compose.yml" "$(compose_files)"
check "tunnel ports: 127.0.0.1 only, as before" "127.0.0.1:8088->80/tcp" "$(web_ports)"
check "tunnel command: the image's (Caddyfile)" null "$(web_json .command)"
check "services: tunnel" "api mcp web cloudflared" "$(up_services 1)"
check "services: tunnel, --no-tunnel" "api mcp web" "$(up_services 0)"
check "tunnel: compose knows cloudflared" cloudflared "$(compose config --services | grep -x cloudflared || true)"
check "tunnel: printed command" "docker compose --env-file $ENV_FILE -f $DIR/docker-compose.yml" "$(compose_command)"
check "the compose project" wambito-personal "$(compose config --format json | jq -r .name)"
check "the database volume" wambito-personal-db "$(compose config --format json | jq -r .volumes.db.name)"
api_url="$(compose config --format json | jq -r .services.api.environment.DATABASE_URL)"
api_user="${api_url#postgres://}"
check "the API's DATABASE_URL user" wambito_app "${api_user%%:*}"
check "the API's database" wambito "${api_url##*/}"
# The admin settings reach the API (empty means no admins: the panel answers 404).
with_env admin ADMIN_USER_IDS=some-id ADMIN_ALLOWED_IPS=203.0.113.0/24
check "the API gets ADMIN_USER_IDS" some-id "$(compose config --format json | jq -r .services.api.environment.ADMIN_USER_IDS)"
check "the API gets ADMIN_ALLOWED_IPS" 203.0.113.0/24 "$(compose config --format json | jq -r .services.api.environment.ADMIN_ALLOWED_IPS)"
# The MCP's key pair: the public half reaches the API, the private half the MCP (and no other).
with_env keys "MCP_WK_PUBLIC_KEY={\"kty\":\"OKP\",\"crv\":\"X25519\",\"x\":\"pub\"}" \
  "MCP_WK_PRIVATE_KEY={\"kty\":\"OKP\",\"crv\":\"X25519\",\"d\":\"priv\",\"x\":\"pub\"}"
check "the API gets the MCP's public key only" '{"kty":"OKP","crv":"X25519","x":"pub"} ' \
  "$(compose config --format json | jq -r '[.services.api.environment.MCP_WK_PUBLIC_KEY, .services.api.environment.MCP_WK_PRIVATE_KEY] | join(" ")')"
check "the MCP gets the private key only" ' {"kty":"OKP","crv":"X25519","d":"priv","x":"pub"}' \
  "$(compose config --format json | jq -r '[.services.mcp.environment.MCP_WK_PUBLIC_KEY, .services.mcp.environment.MCP_WK_PRIVATE_KEY] | join(" ")')"
with_env unset
check "the images" "wambito-api:personal wambito-mcp:personal wambito-web:personal" \
  "$(compose config --format json | jq -r '[.services.api.image, .services.mcp.image, .services.web.image] | join(" ")')"
check "the postgres user and database" "wambito wambito" \
  "$(compose config --format json | jq -r '[.services.postgres.environment.POSTGRES_USER, .services.postgres.environment.POSTGRES_DB] | join(" ")')"
expected_back="To put the previous database back and start the app on it:
  $(compose_command) exec postgres psql -U wambito -d postgres -c 'alter database wambito rename to wambito_restore_X'
  $(compose_command) exec postgres psql -U wambito -d postgres -c 'alter database wambito_before_X rename to wambito'
  $(compose_command) up -d --wait api mcp web"
check "restore: how to go back" "$expected_back" "$(restore_go_back wambito_before_X wambito_restore_X "api mcp web")"

# The plain default, written out, is the same.
with_env written COMPOSE_FILE=docker-compose.yml
check "COMPOSE_FILE=docker-compose.yml: tunnel" tunnel "$(exposure)"

# --- direct. --------------------------------------------------------------------------------------
with_env direct COMPOSE_FILE=docker-compose.yml:docker-compose.direct.yml
check "direct" direct "$(exposure)"
check "direct: both files, in order" "$DIR/docker-compose.yml
$DIR/docker-compose.direct.yml" "$(compose_files)"
check "direct ports" "127.0.0.1:8088->8080/tcp
443->443/tcp
443->443/udp
80->80/tcp" "$(web_ports)"
check "direct ports: nothing else on 8088" "8080" "$(compose config --format json |
  jq -r '[.services.web.ports[] | select(.published == "8088") | .target] | map(tostring) | join(",")')"
case "$(web_json '.command | join(" ")')" in
  *"--config /etc/caddy/Caddyfile.direct "*) ok "direct command: Caddyfile.direct" ;;
  *) fail "direct command: Caddyfile.direct (got '$(web_json .command)')" ;;
esac
check "direct: certificates kept in a volume" "web-caddy-data:/data" \
  "$(web_json '.volumes[] | "\(.source):\(.target)"')"
check "direct: PUBLIC_HOSTNAME for Caddy" app.wambito.com "$(web_json .environment.PUBLIC_HOSTNAME)"
case "$(web_json '.healthcheck.test | join(" ")')" in
  *"http://127.0.0.1:8080/sign-in"*) ok "direct healthcheck: the local listener" ;;
  *) fail "direct healthcheck: the local listener (got '$(web_json .healthcheck.test)')" ;;
esac
check "services: direct" "api mcp web" "$(up_services 1)"
check "services: direct, --no-tunnel" "api mcp web" "$(up_services 0)"
# What a bare `docker compose up -d` would start: everything but cloudflared.
check "direct: a bare compose up has no cloudflared" "" "$(compose config --services | grep -x cloudflared || true)"
check "direct: a bare compose up has the rest" "api mcp migrate postgres web" \
  "$(compose config --services | sort | tr '\n' ' ' | sed 's/ $//')"
check "direct: printed command" \
  "docker compose --env-file $ENV_FILE -f $DIR/docker-compose.yml -f $DIR/docker-compose.direct.yml" \
  "$(compose_command)"

with_env direct-port COMPOSE_FILE=docker-compose.yml:docker-compose.direct.yml WEB_PORT=9099
check "direct ports: WEB_PORT moves the local listener" "127.0.0.1:9099->8080/tcp" \
  "$(web_ports | grep '^127\.0\.0\.1:' || true)"

# --- Sign-in: open to everyone unless SIGN_IN_ALLOWLIST names someone. ----------------------------
ENV_FILE="$tmp/open.env"
printf '%s\n' POSTGRES_PASSWORD=test APP_DB_PASSWORD=test BETTER_AUTH_SECRET=test >"$ENV_FILE"
if open_json="$(compose config --format json 2>/dev/null)"; then
  check "no SIGN_IN_ALLOWLIST: open sign-in (empty)" "" \
    "$(jq -r '.services.api.environment.SIGN_IN_ALLOWLIST // ""' <<<"$open_json")"
else
  fail "no SIGN_IN_ALLOWLIST: compose refuses the .env"
fi
with_env allowlist
check "SIGN_IN_ALLOWLIST is passed on" you@example.com \
  "$(compose config --format json | jq -r .services.api.environment.SIGN_IN_ALLOWLIST)"

# --- What COMPOSE_FILE may name. ------------------------------------------------------------------
refused() { # NAME VALUE: compose_files exits non-zero for COMPOSE_FILE=VALUE
  with_env refused "COMPOSE_FILE=$2"
  if (compose_files >/dev/null 2>&1); then fail "$1 (accepted COMPOSE_FILE=$2)"; else ok "$1"; fi
}
refused "unknown file refused" docker-compose.yml:evil.yml
refused "docker-compose.yml must be first" docker-compose.direct.yml:docker-compose.yml
refused "the override alone refused" docker-compose.direct.yml
refused "a path refused" docker-compose.yml:../docker-compose.direct.yml
refused "an empty entry refused" docker-compose.yml::docker-compose.direct.yml
with_env refused COMPOSE_FILE=docker-compose.yml:evil.yml
if (exposure >/dev/null 2>&1); then fail "exposure fails on an unknown file"; else ok "exposure fails on an unknown file"; fi
if (compose config >/dev/null 2>&1); then fail "compose refuses an unknown file"; else ok "compose refuses an unknown file"; fi

# --- up.sh uses up_services (up.sh builds and deploys for real, so it is checked by reading it). ---
if grep -n 'up_services "$with_tunnel"' "$here/up.sh" >/dev/null; then
  ok "up.sh: starts up_services"
else
  fail "up.sh: starts up_services (no 'up_services \"\$with_tunnel\"' in up.sh)"
fi
# Every line of up.sh that names TUNNEL_ID sits inside the test for cloudflared in that list: the
# cloudflared branch of a `case ... $services ...` (up to its `;;`), or an `if` naming both (up to
# its `fi`).
outside="$(awk '
  /TUNNEL_ID/ && !/^[[:space:]]*#/ { seen = 1; if (!inside) print NR ": " $0 }
  /case .*\$services/ { incase = 1 }
  incase && /cloudflared[^)]*\)/ { inside = 1 }
  /^[[:space:]]*if .*cloudflared.*\$services|^[[:space:]]*if .*\$services.*cloudflared/ { inside = 1 }
  /;;|^[[:space:]]*fi([[:space:]]|$)/ { inside = 0 }
  /esac/ { incase = 0; inside = 0 }
  END { if (!seen) print "no TUNNEL_ID check at all" }
' "$here/up.sh")"
check "up.sh: TUNNEL_ID checked only when cloudflared starts" "" "$outside"

if [ "$failures" -gt 0 ]; then
  printf '\n%s check(s) failed\n' "$failures"
  exit 1
fi
printf '\nall checks passed\n'
