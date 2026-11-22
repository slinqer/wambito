#!/bin/sh
# Fails when a production image would miss a workspace package: every `workspace:` dependency of an
# app, followed through the packages it depends on, must be copied in the app's Dockerfile.prod.
#
# Usage: scripts/check-dockerfile-workspaces.sh [repo-dir] [app-dir ...]
#   (default: this repository, apps/api and apps/mcp)
#
# Rules (kept simple on purpose):
#  - The dependencies are every `workspace:` entry of dependencies, devDependencies,
#    peerDependencies and optionalDependencies (`pnpm install --filter "<app>..."` installs them all),
#    followed transitively; a package is found by its name in apps/*/package.json and
#    packages/*/package.json.
#  - Each one needs its package.json copied before the install: a line
#    `COPY <dir>/package.json <dir>/`.
#  - And its sources before the build: a line `COPY <dir> <dir>`, or `COPY packages packages` for
#    a package under packages/.
# Reads package.json with node (CI's check job has it).
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="${1:-$root}"
[ "$#" -gt 0 ] && shift
[ "$#" -gt 0 ] || set -- apps/api apps/mcp

failures=0
fail() {
  echo "check-dockerfile-workspaces: $*" >&2
  failures=$((failures + 1))
}

for app in "$@"; do
  dockerfile="$repo/$app/Dockerfile.prod"
  if [ ! -f "$dockerfile" ]; then
    fail "$app/Dockerfile.prod does not exist"
    continue
  fi
  deps="$(node -e '
    const fs = require("node:fs");
    const path = require("node:path");
    const [repo, app] = process.argv.slice(1);
    const byName = new Map();
    for (const group of ["apps", "packages"]) {
      const base = path.join(repo, group);
      if (!fs.existsSync(base)) continue;
      for (const entry of fs.readdirSync(base)) {
        const file = path.join(base, entry, "package.json");
        if (!fs.existsSync(file)) continue;
        byName.set(JSON.parse(fs.readFileSync(file, "utf8")).name, `${group}/${entry}`);
      }
    }
    const kinds = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];
    const seen = new Set();
    const queue = [app];
    while (queue.length > 0) {
      const dir = queue.shift();
      const pkg = JSON.parse(fs.readFileSync(path.join(repo, dir, "package.json"), "utf8"));
      for (const kind of kinds) {
        for (const [name, version] of Object.entries(pkg[kind] ?? {})) {
          if (!String(version).startsWith("workspace:")) continue;
          const found = byName.get(name);
          if (!found) {
            console.error(`check-dockerfile-workspaces: ${dir} depends on ${name}, not in the workspace`);
            process.exit(2);
          }
          if (!seen.has(found)) {
            seen.add(found);
            queue.push(found);
          }
        }
      }
    }
    for (const dir of [...seen].sort()) console.log(dir);
  ' "$repo" "$app")"
  for dep in $deps; do
    if ! grep -Eq "^COPY[[:space:]]+${dep}/package\.json[[:space:]]+${dep}/?[[:space:]]*$" "$dockerfile"; then
      fail "$app/Dockerfile.prod does not copy ${dep}/package.json before the install"
    fi
    case "$dep" in
      packages/*) whole='|^COPY[[:space:]]+packages[[:space:]]+packages/?[[:space:]]*$' ;;
      *) whole='' ;;
    esac
    if ! grep -Eq "^COPY[[:space:]]+${dep}[[:space:]]+${dep}/?[[:space:]]*\$${whole}" "$dockerfile"; then
      fail "$app/Dockerfile.prod does not copy the sources of ${dep} before the build"
    fi
  done
done

if [ "$failures" -ne 0 ]; then
  echo "check-dockerfile-workspaces: ${failures} problem(s); copy each package like the others" >&2
  exit 1
fi
echo "check-dockerfile-workspaces: every workspace dependency is copied"
