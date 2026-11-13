#!/usr/bin/env bash
# The phone's vault against the real API (docs: apps/mobile/AGENTS.md). Assumes the root dev stack
# is up (`cp -n .env.example .env; docker compose up -d`, with Mailpit on :8025 and the API on
# :3000): resets the seeded preview account, runs test_stack/vault_e2e_test.dart (tag `stack`),
# then checks in Postgres that no record body holds the movement's name in the clear (a byte
# search: sealed bodies are not valid UTF-8, so convert_from would fail on them).
set -euo pipefail

mobile="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(cd "$mobile/../.." && pwd)"

cd "$root"
docker compose exec -T api pnpm --filter @wambito/api seed:e2e-preview

cd "$mobile"
flutter test --tags stack test_stack/vault_e2e_test.dart

cd "$root"
count="$(docker compose exec -T postgres psql -U wambito -d wambito -tAc \
  "select count(*) from records where position(convert_to('almuerzo','UTF8') in body) > 0")"
echo "records holding the movement's name in the clear: $count"
if [ "$count" != "0" ]; then
  echo "A record body holds the plain text." >&2
  exit 1
fi
