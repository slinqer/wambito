#!/usr/bin/env bash
# CI: installs Playwright Chromium with its system packages. GitHub's Ubuntu runners send apt to an
# Azure mirror (mirror+file:/etc/apt/apt-mirrors.txt); when that mirror stops resolving, every run
# fails here. After a failed attempt this points apt at the main Ubuntu archive and tries again.
# Tested by scripts/test-ci-install-chromium.sh (the variables below are its seams).
set -euo pipefail

mirrors="${APT_MIRRORS_FILE:-/etc/apt/apt-mirrors.txt}"
install="${INSTALL_CMD:-pnpm --filter @wambito/web exec playwright install --with-deps chromium}"
sudo="${SUDO-sudo}"
pause="${RETRY_SLEEP:-15}"
attempts=3

for i in $(seq 1 "$attempts"); do
  if bash -c "$install"; then
    exit 0
  fi
  [ "$i" -eq "$attempts" ] && break
  echo "Chromium install failed (attempt $i of $attempts); switching apt to archive.ubuntu.com"
  printf 'http://archive.ubuntu.com/ubuntu/\tpriority:1\n' | $sudo tee "$mirrors" >/dev/null
  sleep "$pause"
done
echo "Chromium install failed after $attempts attempts" >&2
exit 1
