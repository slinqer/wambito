#!/usr/bin/env bash
# Tests the personal install's Caddy config against real Caddy, in Docker: a private network with a
# fake upstream (answering as `api` on :3000 and `mcp` on :3001 with the X-Forwarded-For it got),
# the Caddy under test (the deploy's Caddy files at their /etc/caddy/ paths, a tiny /srv) and a curl
# client at a fixed address. Needs Docker; everything it starts is removed on exit.
# Run: ./test-caddy.sh [tunnel|direct|all]   (default all: every set below)
#
# What it checks (tunnel, Caddyfile): the client's address reaches the API and the MCP as the only
# X-Forwarded-For entry, taken from Cf-Connecting-Ip when Cloudflare sent one and from the TCP peer
# otherwise, never from the X-Forwarded-For the client sent; the access log names the same visitor;
# the API schema is not public; the landing's paths (landing, roadmap, automatic capture, privacy, account deletion) redirect to LANDING_URL with
# path and query.
#
# What it checks (direct, Caddyfile.direct, as app.localhost with Caddy's internal CA): the client's
# address is always the TCP peer, whatever Cf-Connecting-Ip or X-Forwarded-For it sends, and the log
# says the same; HTTP redirects to HTTPS, which sends HSTS; the plain-HTTP listener on 8080 (for this
# machine only) serves the app without HSTS; a request for any other host never gets the app or the
# API over plain HTTP.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

# The case sets this script knows, in the order `all` runs them. Each NAME has a cases_NAME below.
sets="tunnel direct"

mode="${1:-all}"
case "$mode" in
  all) run_sets="$sets" ;;
  *)
    case " $sets " in
      *" $mode "*) run_sets="$mode" ;;
      *) die "usage: $0 [${sets// /|}|all]" ;;
    esac
    ;;
esac

need_docker

CADDY_IMAGE=caddy:2.11-alpine
CURL_IMAGE=curlimages/curl:8.17.0
LANDING_URL=https://wambito.com
# A fixed subnet, so the client's address is known. Not the install's own (NETWORK_PREFIX).
SUBNET=10.233.71.0/24
CLIENT_IP=10.233.71.10
# The Caddy under test, where a test needs its address (direct: requests that name no host).
WEB_IP=10.233.71.20

id="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)"
net="caddytest-$id"
tmp="$(mktemp -d)"
containers=""
cleanup() {
  local c
  for c in $containers; do docker rm -f "$c" >/dev/null 2>&1 || true; done
  docker network rm "$net" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT
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

# --- The network, the upstream and the client. ------------------------------------------------
docker network create --subnet "$SUBNET" "$net" >/dev/null

mkdir -p "$tmp/upstream" "$tmp/srv"
cat >"$tmp/upstream/Caddyfile" <<'EOF'
{
	auto_https off
	admin off
}
:3000, :3001 {
	respond "{header.X-Forwarded-For}"
}
EOF
printf '<!doctype html><title>index</title>\n' >"$tmp/srv/index.html"
printf '<!doctype html><title>app</title>\n' >"$tmp/srv/__spa-fallback.html"
mkdir -p "$tmp/srv/email/fonts"
printf 'font\n' >"$tmp/srv/email/fonts/f.woff2"
mkdir -p "$tmp/srv/.well-known"
printf '{"applinks":{"details":[]},"webcredentials":{"apps":[]}}\n' >"$tmp/srv/.well-known/apple-app-site-association"

upstream="caddytest-upstream-$id"
containers="$containers $upstream"
docker run -d --name "$upstream" --network "$net" --network-alias api --network-alias mcp \
  -v "$tmp/upstream:/etc/caddy:ro" "$CADDY_IMAGE" >/dev/null

client="caddytest-client-$id"
containers="$containers $client"
docker run -d --name "$client" --network "$net" --ip "$CLIENT_IP" --entrypoint sleep \
  "$CURL_IMAGE" 3600 >/dev/null

# curl_web ARGS...: curl from the client to the Caddy under test (http://web:80 plus the path).
curl_web() { docker exec "$client" curl -s --max-time 10 "$@"; }

# start_web CONFIG [DOCKER_RUN_ARGS...]: runs the Caddy under test with /etc/caddy/CONFIG, as `web`
# on the network (the one from an earlier set is removed first; extra arguments such as `-e NAME=...`
# go to docker run), and waits until port 80 takes connections, whatever it answers there.
web=""
start_web() {
  local config="$1" f rc
  local mounts=()
  shift
  if [ -n "$web" ]; then docker rm -f "$web" >/dev/null 2>&1 || true; fi
  web="caddytest-web-$(printf '%s' "$config" | tr 'A-Z.' 'a-z-')-$id"
  containers="$containers $web"
  # Every Caddy file of the deploy, at the path the image copies it to.
  for f in "$here"/Caddyfile* "$here"/*.caddy; do
    if [ -f "$f" ]; then mounts+=(-v "$f:/etc/caddy/$(basename "$f"):ro"); fi
  done
  docker run -d --name "$web" --network "$net" --network-alias web "${mounts[@]}" \
    -v "$tmp/srv:/srv:ro" -e LANDING_URL="$LANDING_URL" "$@" "$CADDY_IMAGE" \
    caddy run --config "/etc/caddy/$config" --adapter caddyfile >/dev/null
  for _ in $(seq 1 50); do
    rc=0
    curl_web -o /dev/null http://web:80/ || rc=$?
    # 7: nothing listening yet; 6: the name `web` is not there yet.
    [ "$rc" -ne 7 ] && [ "$rc" -ne 6 ] && return 0
    sleep 0.2
  done
  docker logs "$web" 2>&1 | tail -n 20
  die "Caddy with $config did not start"
}

# web_log_has TEXT: whether the Caddy under test logged TEXT, waiting a little for the log to land.
# The log goes to a file first: `docker logs | grep -q` fails under pipefail when grep stops early.
web_log_has() {
  local _
  for _ in $(seq 1 10); do
    docker logs "$web" >"$tmp/web.log" 2>&1 || true
    grep -qF -- "$1" "$tmp/web.log" && return 0
    sleep 0.2
  done
  return 1
}

# log_line_of URI: the access-log line of the request for URI (waiting for it to land), or nothing.
log_line_of() {
  web_log_has "\"uri\":\"$1\"" || return 0
  grep -F -- "\"uri\":\"$1\"" "$tmp/web.log" | tail -n 1
}

# check_log_visitor NAME URI IP: the log line of the request for URI names IP as the visitor.
check_log_visitor() {
  local line
  line="$(log_line_of "$2")"
  case "$line" in
    *"\"visitor_ip\":\"$3\""*) ok "$1" ;;
    "") fail "$1 (no log line for $2)" ;;
    *) fail "$1 (expected \"visitor_ip\":\"$3\" in: $line)" ;;
  esac
}

# --- tunnel: Caddyfile, behind cloudflared. ---------------------------------------------------
cases_tunnel() {
  start_web Caddyfile
  check "tunnel: Cf-Connecting-Ip becomes X-Forwarded-For" 203.0.113.7 \
    "$(curl_web -H 'Cf-Connecting-Ip: 203.0.113.7' -H 'X-Forwarded-For: 198.51.100.9' http://web:80/api/x)"
  check "tunnel: without Cloudflare, the peer" "$CLIENT_IP" \
    "$(curl_web -H 'X-Forwarded-For: 198.51.100.9' http://web:80/api/x)"
  check "tunnel: MCP, Cf-Connecting-Ip becomes X-Forwarded-For" 203.0.113.7 \
    "$(curl_web -X POST -H 'Content-Type: application/json' -d '{}' \
      -H 'Cf-Connecting-Ip: 203.0.113.7' -H 'X-Forwarded-For: 198.51.100.9' http://web:80/mcp)"
  check "tunnel: MCP, without Cloudflare, the peer" "$CLIENT_IP" \
    "$(curl_web -X POST -H 'Content-Type: application/json' -d '{}' \
      -H 'X-Forwarded-For: 198.51.100.9' http://web:80/mcp)"
  # The emails' fonts load in mail clients only with CORS.
  check "tunnel: email fonts allow any origin" "*" \
    "$(curl_web -I http://web:80/email/fonts/f.woff2 | header_of Access-Control-Allow-Origin)"
  check "tunnel: email files cached a day" "public, max-age=86400" \
    "$(curl_web -I http://web:80/email/fonts/f.woff2 | header_of Cache-Control)"
  # Apple reads the association file as JSON though its name has no extension.
  check "tunnel: apple-app-site-association is JSON" "200 application/json" \
    "$(curl_web -o /dev/null -w '%{http_code} %{content_type}' http://web:80/.well-known/apple-app-site-association)"
  check "tunnel: schema not public" 404 \
    "$(curl_web -o /dev/null -w '%{http_code}' http://web:80/api/openapi.json)"
  check "tunnel: landing redirect" "302 $LANDING_URL/pt?x=1" \
    "$(curl_web -o /dev/null -w '%{http_code} %{redirect_url}' 'http://web:80/pt?x=1')"
  # The roadmap and the legal pages (privacy, account deletion) live on the landing too.
  for path in /roadmap /it/roadmap/ /automatic-capture /pt/automatic-capture/ /privacy /en/privacy/ /pt/privacy /delete-account /it/delete-account /en/delete-account/; do
    check "tunnel: $path redirect" "302 $LANDING_URL$path" \
      "$(curl_web -o /dev/null -w '%{http_code} %{redirect_url}' "http://web:80$path")"
  done
  if web_log_has '"visitor_ip":"203.0.113.7"'; then
    ok "tunnel: log has the visitor"
  else
    fail "tunnel: log has the visitor (no \"visitor_ip\":\"203.0.113.7\" in docker logs)"
  fi
  # Without Cloudflare the visitor in the log is the peer too. (This pins the behavior, not the
  # @notViaCloudflare line: Caddy itself starts every request with client_ip set to the peer, since
  # no trusted_proxies is configured, so the log would say the same without that line.)
  curl_web -o /dev/null -H 'X-Forwarded-For: 198.51.100.9' http://web:80/api/log-no-cloudflare
  check_log_visitor "tunnel: without Cloudflare, the log has the peer" /api/log-no-cloudflare "$CLIENT_IP"
}

# --- direct: Caddyfile.direct, on a server with its own public address. -------------------------
# curl_app ARGS...: curl from the client to the Caddy under test as app.localhost (80 and 443),
# accepting the internal CA's certificate.
curl_app() {
  curl_web -k --resolve "app.localhost:443:$WEB_IP" --resolve "app.localhost:80:$WEB_IP" "$@"
}
# header_of NAME: the value of the response header NAME in `curl -I` output on stdin.
header_of() { tr -d '\r' | awk -v name="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" -F': ' 'tolower($1) == name { print $2 }'; }

# nothing NAME HOST CURL_ARGS...: the answer to a request naming HOST is neither the app (the SPA
# shell or index) nor the upstream's echo. A refused connection or failed handshake, a 4xx, an empty
# answer, or a redirect to HTTPS (to app.localhost, or to HOST itself: Caddy's catch-all redirect on
# port 80, after which HOST gets no certificate, checked below) pass.
nothing() {
  local name="$1" host="$2" out meta body code location
  shift 2
  out="$(curl_web -w '\n%{http_code} %{redirect_url}' "$@" || true)"
  meta="${out##*$'\n'}"
  body=""
  case "$out" in *$'\n'*) body="${out%$'\n'*}" ;; esac
  code="${meta%% *}"
  location="${meta#* }"
  case "$body" in
    *"<title>"* | *"$CLIENT_IP"* | *198.51.100.9* | *203.0.113.7*)
      fail "$name (got the app or the upstream: $code '$body')"
      return
      ;;
  esac
  case "$code" in
    000 | 4??) ok "$name ($code)" ;;
    3??)
      case "$location" in
        https://app.localhost/* | https://app.localhost | "https://$host/"*) ok "$name ($code to $location)" ;;
        *) fail "$name (redirect to '$location')" ;;
      esac
      ;;
    *)
      if [ -z "$body" ]; then ok "$name ($code, empty)"; else fail "$name ($code '$body')"; fi
      ;;
  esac
}

cases_direct() {
  local app=https://app.localhost rc
  start_web Caddyfile.direct --ip "$WEB_IP" -e PUBLIC_HOSTNAME=app.localhost
  # The certificate comes from Caddy's internal CA (*.localhost): wait until HTTPS answers.
  for _ in $(seq 1 50); do
    rc=0
    curl_app -o /dev/null "$app/sign-in" || rc=$?
    [ "$rc" -eq 0 ] && break
    sleep 0.2
  done

  check "direct: spoofed Cf-Connecting-Ip ignored" "$CLIENT_IP" \
    "$(curl_app -H 'Cf-Connecting-Ip: 203.0.113.7' -H 'X-Forwarded-For: 198.51.100.9' "$app/api/x")"
  check "direct: MCP, spoofed Cf-Connecting-Ip ignored" "$CLIENT_IP" \
    "$(curl_app -X POST -H 'Content-Type: application/json' -d '{}' \
      -H 'Cf-Connecting-Ip: 203.0.113.7' -H 'X-Forwarded-For: 198.51.100.9' "$app/mcp")"
  check "direct: HTTP goes to HTTPS" "308 $app/sign-in" \
    "$(curl_app -o /dev/null -w '%{http_code} %{redirect_url}' http://app.localhost/sign-in)"
  check "direct: HSTS" "max-age=31536000" \
    "$(curl_app -I "$app/sign-in" | header_of Strict-Transport-Security)"
  check "direct: the app over HTTPS" 200 "$(curl_app -o /dev/null -w '%{http_code}' "$app/sign-in")"
  check "direct: apple-app-site-association is JSON" "200 application/json" \
    "$(curl_app -o /dev/null -w '%{http_code} %{content_type}' "$app/.well-known/apple-app-site-association")"
  check "direct: schema not public" 404 \
    "$(curl_app -o /dev/null -w '%{http_code}' "$app/api/openapi.json")"
  check "direct: landing redirect" "302 $LANDING_URL/pt?x=1" \
    "$(curl_app -o /dev/null -w '%{http_code} %{redirect_url}' "$app/pt?x=1")"
  for path in /roadmap /it/roadmap/ /automatic-capture /pt/automatic-capture/ /privacy /en/privacy/ /pt/privacy /delete-account /it/delete-account /en/delete-account/; do
    check "direct: $path redirect" "302 $LANDING_URL$path" \
      "$(curl_app -o /dev/null -w '%{http_code} %{redirect_url}' "$app$path")"
  done

  check "direct: internal listener" 200 "$(curl_web -o /dev/null -w '%{http_code}' http://web:8080/sign-in)"
  check "direct: internal listener, no HSTS" "" \
    "$(curl_web -I http://web:8080/sign-in | header_of Strict-Transport-Security)"
  check "direct: internal listener, spoofed Cf-Connecting-Ip ignored" "$CLIENT_IP" \
    "$(curl_web -H 'Cf-Connecting-Ip: 203.0.113.7' -H 'X-Forwarded-For: 198.51.100.9' http://web:8080/api/x)"

  nothing "direct: other hosts get nothing (by address)" "$WEB_IP" \
    -H 'Cf-Connecting-Ip: 203.0.113.7' "http://$WEB_IP/sign-in"
  nothing "direct: other hosts get nothing (Host: 127.0.0.1)" 127.0.0.1 -H 'Host: 127.0.0.1' \
    -H 'Cf-Connecting-Ip: 203.0.113.7' "http://$WEB_IP/api/x"
  nothing "direct: other hosts get nothing (Host: 127.0.0.1:8080)" 127.0.0.1 -H 'Host: 127.0.0.1:8080' \
    "http://$WEB_IP/api/x"
  nothing "direct: other hosts get nothing (Host: other.example)" other.example \
    -H 'Host: other.example' "http://$WEB_IP/sign-in?code=other-host-query"
  # Where those redirects lead: HTTPS for any other name has no certificate, so no answer at all.
  nothing "direct: other hosts get nothing (HTTPS by address)" "$WEB_IP" -k "https://$WEB_IP/api/x"
  nothing "direct: other hosts get nothing (HTTPS for other.example)" other.example -k \
    --resolve "other.example:443:$WEB_IP" "https://other.example/sign-in"

  # Last, so every request above has been logged: the peer, never the spoofed address. Requests
  # naming another host are not logged at all (Caddy's default access log would keep their headers
  # and query strings, where sign-in codes travel); the app's host keeps its minimal log.
  curl_app -o /dev/null -H 'Cf-Connecting-Ip: 203.0.113.7' -H 'X-Forwarded-For: 198.51.100.9' "$app/api/log-direct"
  check_log_visitor "direct: log has the peer" /api/log-direct "$CLIENT_IP"
  if grep -qF 203.0.113.7 "$tmp/web.log"; then
    fail "direct: log never has the spoofed address ($(grep -F 203.0.113.7 "$tmp/web.log" | head -n 1))"
  else
    ok "direct: log never has the spoofed address"
  fi
  if grep -qF other-host-query "$tmp/web.log"; then
    fail "direct: other hosts' query strings not logged ($(grep -F other-host-query "$tmp/web.log" | head -n 1))"
  else
    ok "direct: other hosts' query strings not logged"
  fi
  # The app's host on port 80 (the redirect) still lands in the site's log, without its query.
  curl_app -o /dev/null 'http://app.localhost/auth/verify-redirect?code=app-host-query'
  case "$(log_line_of /auth/verify-redirect)" in
    *'"logger":"http.log.access.log'*) ok "direct: HTTP redirect logged by the site's log" ;;
    *) fail "direct: HTTP redirect logged by the site's log ($(log_line_of /auth/verify-redirect))" ;;
  esac
  if grep -qF app-host-query "$tmp/web.log"; then
    fail "direct: the redirect's query string not logged"
  else
    ok "direct: the redirect's query string not logged"
  fi
  # And the local listener keeps its log too.
  curl_web -o /dev/null http://web:8080/api/log-local
  check_log_visitor "direct: local listener logged" /api/log-local "$CLIENT_IP"
}

for s in $run_sets; do "cases_$s"; done

if [ "$failures" -gt 0 ]; then
  printf '\n%s check(s) failed\n' "$failures"
  exit 1
fi
printf '\nall checks passed\n'
