#!/usr/bin/env bash
# Runs the shared crypto vectors on a device with the native cryptography.
# Usage: scripts/run-native-vectors.sh <device-id>   (ids: `flutter devices`)
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <device-id>" >&2; exit 2; }
cd "$(dirname "$0")/.."
exec flutter test integration_test/crypto_vectors_test.dart -d "$1" \
  --dart-define=WAMBITO_VECTORS="$(base64 < ../../packages/crypto/test-vectors.json | tr -d '\n')"
