#!/usr/bin/env bash
# Builds the app the way F-Droid will, from the recipe apps/mobile/fdroid/com.wambito.app.yml, in
# F-Droid's own build server image (registry.gitlab.com/fdroid/fdroidserver:buildserver, what
# fdroiddata's CI builds merge requests in), against a commit of this checkout. Nothing is pushed
# or submitted anywhere: the commit is copied into a scratch bare repository, tagged there
# mobile-v<version> (a test tag that exists nowhere else), and a scratch fdroiddata holds the
# recipe, pointed at that repository and tag, and the srclibs (apps/mobile/fdroid/srclibs, plus
# fdroiddata's own flutter.yml, onnxruntime.yml, abseil-cpp.yml and cpuinfo.yml). In the
# container, like fdroiddata's CI "fdroid build" job:
#   1. `fdroid lint com.wambito.app`, on the recipe as committed;
#   2. `fdroid fetchsrclibs` and `fdroid build --verbose --test --on-server --no-tarball
#      com.wambito.app:<code>`, once per build entry (one per ABI), as the user vagrant; each build
#      gets sudo back first, because --on-server runs the recipe's `sudo:` commands and then removes
#      sudo, as F-Droid's server does (`fdroid build -l` would build only the last entry);
#   3. `fdroid scanner --exit-code` on each APK, then on the source of each build.
# The unsigned APKs, the build logs and this run's log end up in <out>.
#
# Usage, from anywhere (Docker; the image is linux/amd64, emulated on Apple Silicon):
#   apps/mobile/scripts/fdroid-build-local.sh <commit>
#       [--version X.Y.Z]   the test tag's version; default: the recipe's first versionName
#       [--out <dir>]       default: a new temporary directory
#       [--cpus <n>]        processors given to the container (default 4); the native build and
#                           Gradle see only these
#       [--memory <size>]   default 7g (the recipe caps Gradle's heap at 4 GB)
#       [--abi <abi>]       build only the entry of arm64-v8a or armeabi-v7a; default: both
#       [--keep]            leave the container (wambito-fdroid-build) running afterwards, to look
#                           around in it; remove it with `docker rm -f wambito-fdroid-build`. A run
#                           refuses to start while that container exists.
# About an hour per ABI on 4 emulated cores, most of it Vosk's native build.
# Exit codes: 0 lint, the builds and the scanner passed; 1 one of them failed; 2 bad arguments or
# setup.
set -euo pipefail

IMAGE=registry.gitlab.com/fdroid/fdroidserver:buildserver
# fdroidserver from git at a pinned commit, as fdroiddata's CI installs it (master on 2026-10-27).
FDROIDSERVER_REV=cdfdce835a8231996b02392bc79c1879e6bef501
CONTAINER=wambito-fdroid-build
APPID=com.wambito.app

MOBILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPE="$MOBILE/fdroid/$APPID.yml"
SRCLIBS="$MOBILE/fdroid/srclibs"

die() {
  echo "fdroid-build-local: $1" >&2
  exit "${2:-2}"
}
usage() {
  sed -n '/^# Usage/,/^# Exit codes/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

commit="" version="" out="" cpus=4 memory=7g only_abi="" keep=false
while [ $# -gt 0 ]; do
  case "$1" in
    --version | --out | --cpus | --memory | --abi) [ $# -ge 2 ] || usage ;;
  esac
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --cpus) cpus="$2"; shift 2 ;;
    --memory) memory="$2"; shift 2 ;;
    --abi) only_abi="$2"; shift 2 ;;
    --keep) keep=true; shift ;;
    -*) usage ;;
    *) [ -z "$commit" ] || usage; commit="$1"; shift ;;
  esac
done
[ -n "$commit" ] || usage
case "$only_abi" in "" | arm64-v8a | armeabi-v7a) ;; *) die "--abi must be arm64-v8a or armeabi-v7a, not $only_abi." ;; esac
[[ "$cpus" =~ ^[1-9][0-9]*$ ]] || die "--cpus must be a positive number."
command -v docker >/dev/null || die "docker is missing."
[ -f "$RECIPE" ] || die "no recipe at $RECIPE"

root="$(git -C "$MOBILE" rev-parse --show-toplevel)"
sha="$(git -C "$root" rev-parse --verify --quiet "$commit^{commit}")" || die "no commit $commit here."
if [ -z "$version" ]; then
  version="$(sed -n 's/^  - versionName: //p' "$RECIPE" | head -n 1)"
fi
[[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "--version must be X.Y.Z, not '$version'."
# The base code of release.md: X*10000 + Y*100 + Z; the recipe's codes are base*10 + 1 and + 2.
base=$((BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3]))
tag="mobile-v$version"
[ "$(grep -c '^  - versionName: ' "$RECIPE")" -eq 2 ] || die "the recipe must have two build entries."

if [ -z "$out" ]; then out="$(mktemp -d)"; fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"
input="$out/input"
rm -rf "$input" && mkdir -p "$input"

# The commit, alone in a bare repository, with the test tag.
git init --quiet --bare "$input/wambito.git"
git -C "$root" push --quiet "$input/wambito.git" "$sha:refs/heads/fdroid-local" "$sha:refs/tags/$tag"
git -C "$input/wambito.git" symbolic-ref HEAD refs/heads/fdroid-local

# The scratch fdroiddata: the committed recipe (linted as it is), the one pointed at the scratch
# repository and the test tag (built), the srclibs, and fdroiddata's category list for the lint.
data="$input/fdroiddata"
mkdir -p "$data/metadata" "$data/srclibs" "$data/config" "$data/lint/metadata" "$data/lint/config"
cp "$RECIPE" "$data/lint/metadata/$APPID.yml"
cp "$SRCLIBS"/*.yml "$data/srclibs/"
printf 'RepoType: git\nRepo: https://github.com/flutter/flutter.git\n' >"$data/srclibs/flutter.yml"
# fdroiddata's own srclibs the arm64-v8a entry reuses for the precise model (check-fdroid-recipe.sh's
# FDROIDDATA_SRCLIBS), as fdroiddata has them.
for name in onnxruntime abseil-cpp cpuinfo; do
  curl -fsSL "https://gitlab.com/fdroid/fdroiddata/-/raw/master/srclibs/$name.yml" >"$data/srclibs/$name.yml" ||
    die "could not fetch fdroiddata's srclibs/$name.yml."
done
cp -R "$data/srclibs" "$data/lint/srclibs"
awk -v tag="$tag" -v version="$version" -v base="$base" '
  /^Repo: / { print "Repo: /home/vagrant/wambito.git"; next }
  /^  - versionName: / { print "  - versionName: " version; next }
  /^    versionCode: / { n++; print "    versionCode: " base * 10 + n; next }
  /^    commit: / { print "    commit: " tag; next }
  /^CurrentVersion: / { print "CurrentVersion: " version; next }
  /^CurrentVersionCode: / { print "CurrentVersionCode: " base * 10 + 2; next }
  { print }
' "$RECIPE" >"$data/metadata/$APPID.yml"
# (Without its icon lines: the icons are not fetched, and the lint needs only the names.)
curl -fsSL https://gitlab.com/fdroid/fdroiddata/-/raw/master/config/categories.yml |
  grep -v '^  icon: ' >"$data/config/categories.yml" ||
  die "could not fetch fdroiddata's config/categories.yml."
cp "$data/config/categories.yml" "$data/lint/config/categories.yml"
case "$only_abi" in
  "") codes="$((base * 10 + 1)) $((base * 10 + 2))" ;;
  armeabi-v7a) codes="$((base * 10 + 1))" ;;
  arm64-v8a) codes="$((base * 10 + 2))" ;;
esac

# What runs in the container, as root.
cat >"$input/run.sh" <<'RUN'
#!/bin/bash
set -uo pipefail
source /etc/profile.d/bsenv.sh
fail=0
section() { echo; echo "=== $(date -u +%H:%M:%S) $*"; }

section "setup"
apt-get update -q >/dev/null && apt-get install -y -q sudo >/dev/null || exit 2
fdroidserver=/opt/fdroidserver
git init -q "$fdroidserver"
git -C "$fdroidserver" fetch -q --depth 1 https://gitlab.com/fdroid/fdroidserver.git "$FDROIDSERVER_REV" &&
  git -C "$fdroidserver" checkout -q FETCH_HEAD || exit 2
echo "fdroidserver $(git -C "$fdroidserver" rev-parse HEAD)"
cp -a /input/wambito.git "$home_vagrant/wambito.git"
cp -a /input/fdroiddata "$home_vagrant/fdroiddata"
chown -R vagrant:vagrant "$home_vagrant" "$fdroidserver"
chmod 0600 "$home_vagrant"/fdroiddata/config/*.yml "$home_vagrant"/fdroiddata/lint/config/*.yml
fdroid() {
  sudo --preserve-env --user vagrant env PATH="$fdroidserver:$PATH" PYTHONPATH="$fdroidserver:$fdroidserver/examples" \
    PYTHONUNBUFFERED=true HOME="$home_vagrant" GRADLE_USER_HOME="$home_vagrant/.gradle" fdroid "$@"
}

section "fdroid lint (the recipe as committed)"
(cd "$home_vagrant/fdroiddata/lint" && fdroid lint -v "$APPID") || fail=1
section "fdroid lint (the recipe pointed at the test tag)"
(cd "$home_vagrant/fdroiddata" && fdroid lint -v "$APPID") || echo "(only informative)"

cd "$home_vagrant/fdroiddata" || exit 2
for code in $CODES; do
  section "fdroid build $APPID:$code"
  start=$SECONDS
  apt-get install -y -q sudo >/dev/null
  # --on-server expects the srclibs fetched already, as fdroiddata's CI does first.
  fdroid fetchsrclibs --verbose "$APPID:$code" || { fail=1; break; }
  if (unset CI; fdroid build --verbose --test --on-server --no-tarball "$APPID:$code"); then
    echo "built $APPID:$code in $((SECONDS - start)) s"
  else
    echo "FAILED $APPID:$code after $((SECONDS - start)) s"
    fail=1
  fi
  apt-get install -y -q sudo >/dev/null
  mkdir -p /out/logs /out/apk
  cp -a logs/. /out/logs/ 2>/dev/null
  cp -a tmp/*.apk /out/apk/ 2>/dev/null
  [ "$fail" -eq 0 ] || break
done

if [ "$fail" -eq 0 ]; then
  for apk in tmp/"$APPID"_*.apk; do
    section "fdroid scanner $apk"
    fdroid scanner --verbose --exit-code "$apk" || fail=1
  done
  for code in $CODES; do
    section "fdroid scanner $APPID:$code (source)"
    fdroid scanner --verbose --exit-code "$APPID:$code" || fail=1
  done
fi
chown -R "$(stat -c %u /out)" /out 2>/dev/null
section "done, $([ "$fail" -eq 0 ] && echo passed || echo FAILED)"
exit "$fail"
RUN
chmod +x "$input/run.sh"

echo "Building $APPID at $sha as $tag (codes $codes) into $out" >&2
if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
  die "the container $CONTAINER exists (an earlier --keep run?): remove it with docker rm -f $CONTAINER."
fi
# shellcheck disable=SC2329 # called by the EXIT trap
cleanup() {
  if [ "$keep" = true ]; then
    echo "The container $CONTAINER is still running (docker rm -f $CONTAINER)." >&2
  else
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
}
# Before the container starts, so that an interrupt never leaves it behind.
trap cleanup EXIT
# --cpuset-cpus too, so that nproc (the native build's jobs) and Gradle see the same number.
docker run -d --name "$CONTAINER" --platform linux/amd64 --cpus "$cpus" \
  --cpuset-cpus "0-$((cpus - 1))" --memory "$memory" \
  -v "$input:/input:ro" -v "$out:/out" \
  -e FDROIDSERVER_REV="$FDROIDSERVER_REV" -e APPID="$APPID" -e CODES="$codes" \
  "$IMAGE" sleep infinity >/dev/null
status=0
docker exec "$CONTAINER" /input/run.sh 2>&1 | tee "$out/run.log" || status=$?
[ "$status" -le 1 ] || status=2
if [ "$status" -eq 0 ]; then
  echo "Lint, build and scanner passed: $out/apk" >&2
else
  echo "fdroid-build-local: failed, see $out/run.log and $out/logs" >&2
fi
exit "$status"
