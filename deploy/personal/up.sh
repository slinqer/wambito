#!/usr/bin/env bash
# Builds and starts the personal install: the web app, the images, the database, the migrations,
# then the API, the web server and the tunnel. Safe to run again; it never removes volumes.
#
#   ./up.sh                 everything
#   ./up.sh --no-tunnel     everything except the tunnel (checking it on 127.0.0.1 first); the
#                           direct way (COMPOSE_FILE in .env) has no tunnel, so it changes nothing
#   ./up.sh --skip-web      reuse the last web build (apps/web/build-personal)
#   ./up.sh --force         deploy even if the checkout has uncommitted changes to tracked files
#                           or is not on PERSONAL_BRANCH (see .env); refused otherwise
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

with_tunnel=1
build_web=1
force=0
for arg in "$@"; do
  case "$arg" in
    --no-tunnel) with_tunnel=0 ;;
    --skip-web) build_web=0 ;;
    --force) force=1 ;;
    -h | --help)
      sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown option: $arg" ;;
  esac
done

need_env_file
chmod 600 "$ENV_FILE" # it holds passwords and the auth secret
need_docker
guard_checkout "$force"
host="$(cfg PUBLIC_HOSTNAME app.wambito.com)"
web_port="$(cfg WEB_PORT 8088)"

# What runs: cloudflared only in the tunnel way, and not with --no-tunnel (lib.sh, up_services).
services="$(up_services "$with_tunnel")"
case " $services " in
  *" cloudflared "*)
    tunnel_id="$(cfg TUNNEL_ID)"
    [ -n "$tunnel_id" ] || die "TUNNEL_ID is empty in $ENV_FILE. Create the tunnel first (README.md), or run ./up.sh --no-tunnel."
    creds="$(cfg CLOUDFLARED_DIR "$HOME/.cloudflared")/$tunnel_id.json"
    [ -f "$creds" ] || die "Tunnel credentials not found: $creds (README.md, 'The tunnel')."
    ;;
esac

if [ "$build_web" = 1 ]; then
  landing_url="$(cfg LANDING_URL https://wambito.com)"
  say "Building the web app for https://$host"
  command -v pnpm >/dev/null 2>&1 || die "pnpm is not installed (corepack enable)"
  (
    cd "$REPO_DIR"
    pnpm install --frozen-lockfile
    # Its own folder: apps/web/build/client holds the landing release and must stay as it is.
    rm -rf apps/web/build-personal
    # `/` redirects to the public landing (Caddyfile), so the app's own links to it leave too.
    VITE_SITE_URL="https://$host" VITE_LANDING_ONLY=false WAMBITO_BUILD_DIR=build-personal \
      VITE_LANDING_URL="$landing_url" VITE_BUILD_ID="$(git -C "$REPO_DIR" rev-parse --short HEAD)" \
      pnpm --filter @wambito/web build
  )
fi
[ -f "$REPO_DIR/apps/web/build-personal/client/index.html" ] ||
  die "No web build in apps/web/build-personal. Run ./up.sh without --skip-web."

ensure_volume

say "Building the images"
# The API reports this as its version (Settings in the app shows it): the root package.json's
# version plus the commit, e.g. 1.0.0+1e5ccc2 (server_version in lib.sh).
WAMBITO_VERSION="$(server_version "$REPO_DIR")"
export WAMBITO_VERSION
compose build

say "Starting the database"
compose up -d --wait postgres

say "Applying migrations (creates the wambito_app role the first time)"
compose run --rm migrate

say "Starting: $services"
# shellcheck disable=SC2086
compose up -d --wait $services

say "Running"
compose ps
echo
echo "Check it from this machine:  ./smoke.sh   (http://127.0.0.1:$web_port)"
# Public once the tunnel runs, and always in the direct way (Caddy answers on 80 and 443).
case " $services " in *" cloudflared "*) public=1 ;; *) public=0 ;; esac
[ "$(exposure)" = direct ] && public=1
[ "$public" = 1 ] && echo "On the internet:             https://$host"
exit 0
