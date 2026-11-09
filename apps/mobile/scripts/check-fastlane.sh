#!/usr/bin/env bash
# Checks the store metadata in fastlane/metadata/android (F-Droid reads it, Google Play gets the same
# texts and images) against the stores' limits and against itself: every listing (es-419, es-ES,
# en-US, it-IT, pt-PT) has a title (30 characters at most), a short description (80), a full
# description (4000) and changelogs of 500 bytes at most named for a version code, the same in all of
# them; at least 2 phone screenshots, the same number in all, JPEG or PNG, 320 to 1080 pixels wide,
# 2400 high at most and no longer than twice their short side (Play's rule), small (the repo is not
# an image store); and a feature graphic, JPEG or PNG, exactly 1024x500 and 1 MB at most. The
# screenshots and the feature graphic are made by tool/store_shots. Run from anywhere:
#
#   apps/mobile/scripts/check-fastlane.sh
# Exit codes: 0 fine, 1 something is off.
set -uo pipefail

MOBILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
META="$MOBILE/fastlane/metadata/android"
LOCALES=(es-419 es-ES en-US it-IT pt-PT)
MAX_SCREENSHOT_BYTES=250000
MAX_FEATURE_BYTES=1000000
failed=0
fail() { echo "fastlane: $1"; failed=1; }

# image <file>: prints "<width> <height>" of a JPEG or PNG, or fails and prints nothing.
image() {
  local magic description
  magic="$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')"
  case "$magic" in
    89504e470d0a1a0a) od -An -tu1 -j16 -N8 "$1" | awk '{ print $1*16777216+$2*65536+$3*256+$4, $5*16777216+$6*65536+$7*256+$8 }' ;;
    ffd8ff*)
      # `file` names a JPEG's size after its sample precision ("precision 8, 1080x1920").
      description="$(file -b "$1")"
      [[ "$description" =~ precision\ [0-9]+,\ ([0-9]+)x([0-9]+) ]] || return 1
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
      ;;
    *) return 1 ;;
  esac
}

chars() { LC_ALL=en_US.UTF-8 wc -m <"$1" | tr -d ' '; }

# limit <file> <max characters>: the text, without its final newline, fits.
limit() {
  [ -s "$1" ] || { fail "${1#"$MOBILE"/} is missing or empty"; return; }
  local n
  n="$(chars "$1")"
  n=$((n - 1))
  [ "$n" -le "$2" ] || fail "${1#"$MOBILE"/} is $n characters, over $2"
}

for locale in "${LOCALES[@]}"; do
  dir="$META/$locale"
  [ -d "$dir" ] || { fail "no folder for $locale"; continue; }
  limit "$dir/title.txt" 30
  limit "$dir/short_description.txt" 80
  limit "$dir/full_description.txt" 4000

  codes="$(cd "$dir/changelogs" 2>/dev/null && ls | sort | tr '\n' ' ')"
  [ -n "$codes" ] || fail "$locale has no changelogs"
  for file in "$dir"/changelogs/*; do
    [ -e "$file" ] || continue
    name="$(basename "$file")"
    [[ "$name" =~ ^[1-9][0-9]*\.txt$ ]] || fail "changelogs/$name is not <versionCode>.txt"
    [ "$(wc -c <"$file")" -le 500 ] || fail "$locale/changelogs/$name is over 500 bytes"
  done
  if [ "$locale" = "${LOCALES[0]}" ]; then reference_codes="$codes"; fi
  [ "$codes" = "$reference_codes" ] || fail "$locale changelogs ($codes) differ from ${LOCALES[0]}'s ($reference_codes)"

  count=0
  for shot in "$dir"/images/phoneScreenshots/*; do
    [ -e "$shot" ] || continue
    count=$((count + 1))
    name="${shot#"$MOBILE"/}"
    size="$(image "$shot")" || { fail "$name is not a JPEG or a PNG"; continue; }
    read -r width height <<<"$size"
    bytes=$(($(wc -c <"$shot")))
    [ "$bytes" -le "$MAX_SCREENSHOT_BYTES" ] || fail "$name is $bytes bytes, over $MAX_SCREENSHOT_BYTES"
    if [ "$width" -gt 1080 ] || [ "$height" -gt 2400 ] || [ "$width" -lt 320 ] || [ "$height" -gt $((width * 2)) ] || [ "$width" -gt $((height * 2)) ]; then
      fail "$name is ${width}x${height}: phone screenshots 320 to 1080 wide, 2400 high at most, sides within 2:1"
    fi
  done
  [ "$count" -ge 2 ] || fail "$locale needs at least 2 phone screenshots (has $count)"
  if [ "$locale" = "${LOCALES[0]}" ]; then reference_count="$count"; fi
  [ "$count" -eq "$reference_count" ] || fail "$locale has $count screenshots, ${LOCALES[0]} has $reference_count"

  features=("$dir"/images/featureGraphic.*)
  if [ ! -e "${features[0]}" ] || [ "${#features[@]}" -ne 1 ]; then
    fail "$locale needs one images/featureGraphic.jpg (or .png)"
  else
    feature="${features[0]}"
    name="${feature#"$MOBILE"/}"
    if size="$(image "$feature")"; then
      [ "$size" = "1024 500" ] || fail "$name is ${size/ /x}, not 1024x500"
    else
      fail "$name is not a JPEG or a PNG"
    fi
    [ "$(($(wc -c <"$feature")))" -le "$MAX_FEATURE_BYTES" ] || fail "$name is over $MAX_FEATURE_BYTES bytes"
  fi
done

[ "$failed" -eq 0 ] && echo "Store metadata fine: ${LOCALES[*]}"
exit "$failed"
