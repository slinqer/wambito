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
import { createLocalBackend, type UnavailableRoute } from "../app/local/backend.ts";
import { createMemoryStore } from "../app/local/memory-store.ts";
import type { RecordType } from "../app/local/store.ts";

const DIR = join(import.meta.dirname, "../../mobile/test/fixtures/local_backend");

/** What `vault-session.ts` turns off (`LOCAL_UNAVAILABLE`). */
const UNAVAILABLE: UnavailableRoute[] = [
  { method: "*", path: "/v1/me/export" },
  { method: "*", path: "/v1/imports", prefix: true },
  { method: "*", path: "/v1/me/assistants", prefix: true },
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
    unavailable: UNAVAILABLE,
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
  const out = {
    name: scenario.name,
    status: response.status,
    body: text ? JSON.parse(text) : null,
  };
  writeFileSync(join(DIR, `${scenario.name}.json`), `${JSON.stringify(out, null, 2)}\n`);
  console.log(`${scenario.name}: ${response.status}`);
}
