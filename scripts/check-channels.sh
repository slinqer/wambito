#!/bin/sh
# Fails when a native channel or method the Dart code calls is missing on one of the phones.
#
# Usage: scripts/check-channels.sh [mobile-dir]   (default apps/mobile)
#
# Rules (kept simple on purpose):
#  - A channel is every MethodChannel('wambito/...') / EventChannel('wambito/...') name in lib/.
#  - A method is a quoted first argument of invokeMethod(...) or _call(...) in a Dart file; it
#    belongs to the channels declared in that same file. Only Dart -> native calls count; methods
#    native sends to Dart (e.g. linkArrived) are out of scope, and so are third-party plugins.
#  - A channel is present on a phone when its quoted name appears in some .kt (android/app/src/main/
#    kotlin) or .swift (ios/Runner) file. A method is present when its quoted name appears in a
#    native file that also contains the quoted name of any of the Dart file's channels.
#  - Channels listed in the allowlist (default .github/channel-allowlist.txt, or CHANNEL_ALLOWLIST;
#    one `<channel>  # <reason>` per line) are skipped. A line with no reason, or a reason not in
#    ios-impossible, ios-part-two, android-only, fails.
# POSIX sh and POSIX grep/sed only: it runs the same on macOS and Ubuntu.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
mobile="${1:-apps/mobile}"
case "$mobile" in /*) ;; *) mobile="${PWD}/${mobile}" ;; esac
[ -d "$mobile/lib" ] || mobile="${root}/${1:-apps/mobile}"
allowlist="${CHANNEL_ALLOWLIST:-$root/.github/channel-allowlist.txt}"
known_reasons="ios-impossible ios-part-two android-only"
kotlin="$mobile/android/app/src/main/kotlin"
swift="$mobile/ios/Runner"

trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

failures=0
fail() {
  echo "check-channels: $*" >&2
  failures=$((failures + 1))
}

allowed=""
bad_lines=0
while IFS= read -r line || [ -n "$line" ]; do
  spec="$(printf '%s' "${line%%#*}" | trim)"
  [ -n "$spec" ] || continue
  reason=""
  case "$line" in *"#"*) reason="$(printf '%s' "${line#*#}" | trim)" ;; esac
  ok=0
  for known in $known_reasons; do
    [ "$reason" = "$known" ] && ok=1
  done
  if [ "$ok" -eq 0 ]; then
    echo "check-channels: unknown reason in ${allowlist}: ${line}" >&2
    bad_lines=$((bad_lines + 1))
  fi
  allowed="${allowed}${spec}
"
done <"$allowlist"
if [ "$bad_lines" -ne 0 ]; then
  echo "check-channels: each line needs a reason from: ${known_reasons}." >&2
  exit 1
fi

is_allowed() { printf '%s' "$allowed" | grep -qxF -e "$1"; }

# native_files <dir> <channel>: native files in <dir> holding the quoted channel name.
native_files() {
  grep -rlF --include='*.kt' --include='*.swift' -e "\"$2\"" "$1" 2>/dev/null || true
}

check_dart_file() {
  dart="$1"
  rel="${dart#"$mobile"/}"
  flat="$(tr '\n' ' ' <"$dart")"
  channels="$(printf '%s' "$flat" | grep -oE "(Method|Event)Channel\('wambito/[^']*'" | sed "s/.*('//;s/'\$//" | sort -u || true)"
  methods="$(printf '%s' "$flat" | grep -oE "(invokeMethod|_call)(<[^(]*>)?\([^'();]*'[A-Za-z0-9_]+'" | sed "s/.*'\([A-Za-z0-9_]*\)'\$/\1/" | sort -u || true)"

  kt_files=""
  sw_files=""
  checked=0
  while IFS= read -r channel; do
    [ -n "$channel" ] || continue
    is_allowed "$channel" && continue
    checked=1
    k="$(native_files "$kotlin" "$channel")"
    s="$(native_files "$swift" "$channel")"
    [ -n "$k" ] || fail "channel ${channel} (${rel}) is missing on android"
    [ -n "$s" ] || fail "channel ${channel} (${rel}) is missing on ios"
    kt_files="${kt_files}${k}
"
    sw_files="${sw_files}${s}
"
  done <<END_CHANNELS
$channels
END_CHANNELS

  # With every channel of the file allowlisted there is nothing to hold its methods against.
  [ "$checked" -eq 1 ] || return 0

  while IFS= read -r method; do
    [ -n "$method" ] || continue
    for side in android ios; do
      if [ "$side" = android ]; then files="$kt_files"; else files="$sw_files"; fi
      # A side whose channel is missing was already reported above.
      [ -n "$(printf '%s' "$files" | tr -d '\n')" ] || continue
      found=0
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        if grep -qF -e "\"$method\"" "$f"; then found=1; break; fi
      done <<END_FILES
$files
END_FILES
      [ "$found" -eq 1 ] || fail "method ${method} (${rel}) is missing on ${side}"
    done
  done <<END_METHODS
$methods
END_METHODS
}

for dart in $(find "$mobile/lib" -name '*.dart' | sort); do
  check_dart_file "$dart"
done

if [ "$failures" -ne 0 ]; then
  echo "check-channels: ${failures} problem(s). Add the missing native side, or (only if the phone truly" >&2
  echo "cannot) list the channel in ${allowlist} with a reason." >&2
  exit 1
fi
echo "check-channels: ok"
