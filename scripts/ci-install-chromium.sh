#!/usr/bin/env bash
# CI: installs Playwright Chromium. `--with-deps` also installs system packages through apt, and
# when the runner cannot reach the Ubuntu archives that step fails every run. The ubuntu-24.04
# runner image already ships Chrome's libraries, and apt only adds fonts; no web test compares
# screenshots, so after a failed apt step this installs the browser alone.
# Tested by scripts/test-ci-install-chromium.sh (the two variables are its seams).
set -euo pipefail

with_deps="${WITH_DEPS_CMD:-pnpm --filter @wambito/web exec playwright install --with-deps chromium}"
browser_only="${BROWSER_ONLY_CMD:-pnpm --filter @wambito/web exec playwright install chromium}"

if bash -c "$with_deps"; then
  exit 0
fi
echo "::warning::Chromium install with system packages failed; installing it without system packages"
bash -c "$browser_only"
