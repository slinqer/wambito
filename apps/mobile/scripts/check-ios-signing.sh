#!/bin/sh
# Fails if the iOS project carries a signing team id or tracks the local signing file.
# The team id lives only in the git-ignored ios/Flutter/Signing.xcconfig
# (copy Signing.xcconfig.example).
#
# Usage: scripts/check-ios-signing.sh [ios-dir]   (default: ios, relative to the current directory)
# Exit codes: 0 clean, 1 a problem, named on stderr.
dir="${1:-ios}"
status=0

for f in "$dir"/*.xcodeproj/project.pbxproj; do
  [ -f "$f" ] || continue
  if grep -Eq 'DEVELOPMENT_TEAM(\[[^]]*\])?"? = "?[A-Za-z0-9]+"?;' "$f"; then
    echo "check-ios-signing: $f sets DEVELOPMENT_TEAM; keep it in ios/Flutter/Signing.xcconfig only" >&2
    status=1
  fi
done

if [ -n "$(git -C "$dir" ls-files -- Flutter/Signing.xcconfig 2>/dev/null)" ]; then
  echo "check-ios-signing: $dir/Flutter/Signing.xcconfig is tracked by git; remove it from the index" >&2
  status=1
fi

exit "$status"
