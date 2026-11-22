#!/usr/bin/env bash
# The phone's vault against the real API (docs: apps/mobile/AGENTS.md). Assumes the root dev stack
# is up (`cp -n .env.example .env; docker compose up -d`, with Mailpit on :8025 and the API on
# :3000; after pulling new API code, `docker compose up -d --build api`), with
# `NEW_USERS_ENCRYPTED=true` (`NEW_USERS_ENCRYPTED=true docker compose up -d --build`): it first
# checks that a fresh guest's `GET /v1/me` says `preview`, and stops otherwise. Then the three stack
# tests (tag `stack`), one after the other:
# - test_stack/vault_e2e_test.dart: set up, a movement, a second phone unlocks;
# - test_stack/vault_3b_e2e_test.dart: pairing, background capture and sync, device removal, a new
#   recovery key;
#   (both on the freshly reset seeded preview account, which they share)
# - test_stack/phone_first_e2e_test.dart: the first run without email, protected and given an
#   email; a guest merged into an account; a recovery-key sign-in; a web sign-in approved. Its own
#   new users, whose ids it writes to a report file.
# After each it checks in Postgres that the accounts have records (so the next checks are not
# vacuous), that no record body holds the test's words in the clear (a byte search: sealed bodies
# are not valid UTF-8, so convert_from would fail on them), and that the plain /v1 tables
# (`transactions`, `categories`) hold nothing of the accounts; after the third, that the merged
# guest's user row is gone.
#
# The first two sign in with an email code, and the API allows 5 codes per address in 10 minutes
# (kept in memory): a third run inside that window gets a 429; `docker compose restart api` resets
# it. The third uses new addresses each run.
set -euo pipefail

mobile="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(cd "$mobile/../.." && pwd)"

api="${WAMBITO_E2E_API:-http://localhost:3000}"

sql() { (cd "$root" && docker compose exec -T postgres psql -U wambito -d wambito -tAc "$1"); }

# New users must be encrypted (`preview`): the phone-first test needs it, and so does ruling 19.
guest_token="$(curl -sf -D - -o /dev/null -X POST "$api/api/auth/sign-in/anonymous" \
  -H 'content-type: application/json' -H "x-forwarded-for: 10.78.$((RANDOM % 250)).$((RANDOM % 250 + 1))" \
  -d '{}' | tr -d '\r' | grep -i '^set-auth-token:' | cut -d' ' -f2 || true)"
me="$(curl -sf "$api/api/v1/me" -H "authorization: Bearer ${guest_token:-none}" || true)"
case "$me" in
  *'"encryption":"preview"'*) ;;
  *)
    echo "A new guest is not preview: start the stack with NEW_USERS_ENCRYPTED=true" \
      "(NEW_USERS_ENCRYPTED=true docker compose up -d --build)." >&2
    exit 1
    ;;
esac
echo "a new guest is preview"

# check <account id>: it has records, and no rows in the plain /v1 tables.
check() {
  local id="$1" records plain
  records="$(sql "select count(*) from records where user_id = '$id'")"
  echo "records of $id: $records"
  if ! [ "$records" -gt 0 ] 2>/dev/null; then
    echo "The account $id has no records: the checks below would prove nothing." >&2
    exit 1
  fi

  plain="$(sql "select (select count(*) from transactions where user_id = '$id')
    + (select count(*) from categories where user_id = '$id')")"
  echo "rows of $id in the /v1 tables (transactions, categories): $plain"
  if [ "$plain" != "0" ]; then
    echo "The account $id has rows in the plain /v1 tables." >&2
    exit 1
  fi
}

# no_plain <word>: no record body holds it in the clear.
no_plain() {
  local word="$1" count
  count="$(sql "select count(*) from records where position(convert_to('$word','UTF8') in body) > 0")"
  echo "records holding '$word' in the clear: $count"
  if [ "$count" != "0" ]; then
    echo "A record body holds the plain text." >&2
    exit 1
  fi
}

# run <test file> <word that must never be in a record body in the clear>: on the seeded account.
run() {
  local file="$1" word="$2"
  (cd "$root" && docker compose exec -T api pnpm --filter @wambito/api seed:e2e-preview)
  (cd "$mobile" && flutter test --tags stack "$file")
  check preview-e2e
  no_plain "$word"
}

run test_stack/vault_e2e_test.dart almuerzo
run test_stack/vault_3b_e2e_test.dart panaderia

# The phone-first flows, on users of their own: the test writes their ids (`account=`,
# `mergedGuest=`) to the report.
report="$(mktemp)"
trap 'rm -f "$report"' EXIT
(cd "$mobile" && WAMBITO_E2E_REPORT="$report" flutter test --tags stack \
  test_stack/phone_first_e2e_test.dart)
accounts="$(sed -n 's/^account=//p' "$report")"
merged="$(sed -n 's/^mergedGuest=//p' "$report")"
if [ "$(echo "$accounts" | grep -c .)" != "2" ] || [ -z "$merged" ]; then
  echo "The phone-first test did not report its accounts and merged guest." >&2
  exit 1
fi
for id in $accounts; do check "$id"; done
no_plain cafeteria
no_plain mercado
left="$(sql "select count(*) from \"user\" where id = '$merged'")"
echo "user rows of the merged guest $merged: $left"
if [ "$left" != "0" ]; then
  echo "The merged guest's user is still there." >&2
  exit 1
fi
