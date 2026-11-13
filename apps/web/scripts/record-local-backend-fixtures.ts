/**
 * The phone's local-backend fixtures: for each scenario in
 * apps/mobile/test/fixtures/local_backend/scenarios.json, the answer this app's `createLocalBackend`
 * gives over a memory store seeded from seed.json, saved as <name>.json next to it. The phone's
 * `backend_shapes_test.dart` seeds its own memory store the same way and must answer the same.
 *
 * Same inputs as the Dart test: the clock is pinned and the new ids count up from the same
 * counter, so nothing in the files depends on the day they were recorded.
 *
 *   pnpm --filter @wambito/web record:local-backend
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createLocalBackend } from "../app/local/backend.ts";
import { createMemoryStore } from "../app/local/memory-store.ts";
import type { RecordType } from "../app/local/store.ts";
import { LOCAL_UNAVAILABLE } from "../app/local/vault-session.ts";

const DIR = join(import.meta.dirname, "../../mobile/test/fixtures/local_backend");

const TYPES: RecordType[] = [
  "transaction",
  "category",
  "budget",
  "recurrence",
  "merchant",
  "settings",
  "account",
];

const NOW = new Date("2026-10-21T18:00:00Z");

interface Scenario {
  name: string;
  method: string;
  path: string;
  query?: Record<string, string | string[]>;
  body?: unknown;
}

type Seed = Record<string, { id: string; body: never; deleted?: boolean }[]>;

const seed = JSON.parse(readFileSync(join(DIR, "seed.json"), "utf8")) as Seed;
const scenarios = JSON.parse(readFileSync(join(DIR, "scenarios.json"), "utf8")) as Scenario[];

for (const scenario of scenarios) {
  const store = createMemoryStore();
  await store.transaction(async (s) => {
    for (const [type, records] of Object.entries(seed)) {
      for (const r of records) {
        await s.put(type as RecordType, r.id, r.body);
        if (r.deleted) await s.delete(type as RecordType, r.id);
      }
    }
  });
  let counter = 0x900;
  const backend = createLocalBackend({
    store,
    now: () => new Date(NOW),
    unavailable: LOCAL_UNAVAILABLE,
    profile: { id: "u1", email: "ana@example.test", isAnonymous: false, encryption: "preview" },
    newId: () => `01930000-0000-7000-8000-${(counter++).toString(16).padStart(12, "0")}`,
  });
  const url = new URL(`http://local.test/api${scenario.path}`);
  for (const [name, value] of Object.entries(scenario.query ?? {})) {
    for (const v of Array.isArray(value) ? value : [value]) url.searchParams.append(name, v);
  }
  const hasBody = scenario.body !== undefined;
  const response = await backend.fetch(url, {
    method: scenario.method,
    ...(hasBody ? { body: JSON.stringify(scenario.body) } : {}),
  });
  const text = await response.text();
  // A write's side effects: every record, tombstones included, so the phone's store must end
  // the same as this one.
  const stored: Record<string, unknown[]> = {};
  if (scenario.method !== "GET") {
    for (const type of TYPES) {
      const records = await store.list(type, { includeDeleted: true });
      if (records.length > 0) stored[type] = records;
    }
  }
  const out = {
    name: scenario.name,
    status: response.status,
    body: text ? JSON.parse(text) : null,
    ...(scenario.method !== "GET" ? { store: stored } : {}),
  };
  writeFileSync(join(DIR, `${scenario.name}.json`), `${JSON.stringify(out, null, 2)}\n`);
  console.log(`${scenario.name}: ${response.status}`);
}
