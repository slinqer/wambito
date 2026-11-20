#!/usr/bin/env bash
# Lists the switch day's date markers still left in the privacy policy (the web's site catalogs
# under apps/web/app/i18n and docs/privacy-policy.md) and fails while any is left. The runbook
# (docs/deploy/switch-day.md, "The copy, on the day") runs it before the merge; CI does not, since
# the markers stay in the branch until that day.
#
# Two markers (spelled in pieces below, so this file is not a hit of its own):
#   <MARKER>_PLUS_14   the switch day plus 14 days: replace it FIRST,
#   <MARKER>           the switch day itself,
# each with the bare date in the page's language (es "21 de noviembre de 2026", en "21 November
# 2026", it "21 novembre 2026", pt "21 de novembro de 2026"; the words around it carry the article).
#
#   scripts/check-switch-dates.sh     exit 0: none left; exit 1: prints each file:line left
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
marker="SWITCH""_DATE"

hits="$(grep -rnE "${marker}(_PLUS_14)?" "$ROOT/apps/web/app/i18n" "$ROOT/docs/privacy-policy.md" 2>/dev/null |
  sed "s|^$ROOT/||")"
if [ -n "$hits" ]; then
  echo "switch dates: markers left (replace ${marker}_PLUS_14 first, then ${marker}):"
  echo "$hits" | cut -c1-160
  exit 1
fi
echo "switch dates: none left"
