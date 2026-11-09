#!/usr/bin/env bash
# Takes the raw store screenshots (tool/store_shots/shots_test.dart) for each listing locale on a
# running emulator, against the dev stack (`docker compose up -d` at the repo root). For each locale
# it sets the emulator's language and time zone (the guest's currency follows them: COP, EUR, USD),
# reboots it, then runs `flutter drive`. Needs a rootable emulator image (AOSP).
#
#   apps/mobile/tool/store_shots/run.sh [-d <device>] [locale...]   (default: all five)
#
# Writes apps/mobile/build/store_shots/<locale>/{1_home,2_add,3_capture,4_review,5_budgets,6_insights}.png
# (git-ignored); tool/store_shots/compose.cjs turns them into the listing images.
set -euo pipefail

MOBILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
device="emulator-5554"
if [ "${1:-}" = "-d" ]; then device="$2"; shift 2; fi
case "$device" in
  emulator-*) ;;
  *) echo "run.sh: '$device' is not an emulator: these screenshots sign a guest in and change the phone's language." >&2; exit 2 ;;
esac
locales=("$@")
[ ${#locales[@]} -gt 0 ] || locales=(es-CO es-ES en-US it-IT pt-PT)

zone_for() {
  case "$1" in
    es-CO) echo America/Bogota ;;
    es-ES) echo Europe/Madrid ;;
    en-US) echo America/New_York ;;
    it-IT) echo Europe/Rome ;;
    pt-PT) echo Europe/Lisbon ;;
    *) echo "run.sh: no time zone for $1" >&2; return 1 ;;
  esac
}

# One locale on the emulator: language and time zone, a full reboot, then the screenshots.
take() {
  local locale="$1" zone
  zone="$(zone_for "$locale")" || return 1
  echo "== $locale ($zone)"
  adb -s "$device" wait-for-device
  adb -s "$device" root >/dev/null
  adb -s "$device" wait-for-device
  adb -s "$device" shell "setprop persist.sys.locale $locale; setprop persist.sys.timezone $zone"
  # A full reboot: restarting only the framework (stop; start) leaves Android 16 half up.
  adb -s "$device" reboot
  adb -s "$device" wait-for-device
  until [ "$(adb -s "$device" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
  sleep 15
  # The emulator's automatic time zone (the host's) would win over the property: switch it off and
  # set the zone again, then check it, since the guest's currency follows it (USD for New York).
  adb -s "$device" shell "settings put global auto_time_zone 0; cmd alarm set-timezone $zone"
  local now
  now="$(adb -s "$device" shell getprop persist.sys.timezone | tr -d '\r')"
  [ "$now" = "$zone" ] || { echo "run.sh: the emulator's time zone is $now, not $zone" >&2; return 1; }
  # At most 15 minutes per locale (macOS has no `timeout`): a test stuck on a hidden app would
  # otherwise wait for ever.
  SHOTS_OUT="$MOBILE/build/store_shots/$locale" perl -e 'alarm shift; exec @ARGV' 900 \
    flutter drive -d "$device" \
    --driver=tool/store_shots/driver.dart --target=tool/store_shots/shots_test.dart \
    --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000 --dart-define=SHOTS_LOCALE="$locale" \
    --dart-define=WAMBITO_CLIENT_IP="10.77.$((RANDOM % 250)).$((RANDOM % 250))"
}

# Each locale gets a second try (the emulator drops a connection or a pixel copy now and then);
# one that fails twice is reported at the end and the others still run.
cd "$MOBILE"
failed=()
for locale in "${locales[@]}"; do
  take "$locale" || { echo "== $locale failed, once more"; take "$locale"; } || failed+=("$locale")
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "run.sh: failed: ${failed[*]}" >&2
  exit 1
fi
