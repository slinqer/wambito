#!/usr/bin/env bash
# The phone's vault against the real API (docs: apps/mobile/AGENTS.md). Assumes the root dev stack
# is up (`cp -n .env.example .env; docker compose up -d`, with Mailpit on :8025 and the API on
# :3000): resets the seeded preview account, runs test_stack/vault_e2e_test.dart (tag `stack`),
# then checks in Postgres that the account has records (so the next check is not vacuous), that no
# record body holds the movement's name in the clear (a byte search: sealed bodies are not valid
# UTF-8, so convert_from would fail on them), and that the plain /v1 tables (`transactions`,
# `categories`) hold nothing of the account.
set -euo pipefail

mobile="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(cd "$mobile/../.." && pwd)"

cd "$root"
docker compose exec -T api pnpm --filter @wambito/api seed:e2e-preview

cd "$mobile"
flutter test --tags stack test_stack/vault_e2e_test.dart

cd "$root"
sql() { docker compose exec -T postgres psql -U wambito -d wambito -tAc "$1"; }

records="$(sql "select count(*) from records where user_id = 'preview-e2e'")"
echo "records of preview-e2e: $records"
if ! [ "$records" -gt 0 ] 2>/dev/null; then
  echo "The preview account has no records: the checks below would prove nothing." >&2
  exit 1
fi

plain="$(sql "select (select count(*) from transactions where user_id = 'preview-e2e')
  + (select count(*) from categories where user_id = 'preview-e2e')")"
echo "rows of preview-e2e in the /v1 tables (transactions, categories): $plain"
if [ "$plain" != "0" ]; then
  echo "The preview account has rows in the plain /v1 tables." >&2
  exit 1
fi

count="$(sql "select count(*) from records where position(convert_to('almuerzo','UTF8') in body) > 0")"
echo "records holding the movement's name in the clear: $count"
if [ "$count" != "0" ]; then
  echo "A record body holds the plain text." >&2
  exit 1
fi
