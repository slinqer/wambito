import {
  addMonths,
  firstDay,
  monthOf,
  occurrences,
  type RecordBodies,
  todayIn,
} from "@wambito/core";
import { createLocalBackend, DEMO_UNAVAILABLE } from "../local/backend.ts";
import { createMemoryStore } from "../local/memory-store.ts";
import type { FinanceStore } from "../local/store.ts";
import type { DemoSeed } from "./demo-data.ts";

/**
 * The demo's backend: the seed laid over the calendar, in a memory store, behind the local backend
 * (`../local/backend.ts`), which is the `fetch` that `ApiProvider` hands to the screens
 * (`<ApiProvider mode="demo" fetch={demo.fetch}>`). It answers the `/api/v1/*` routes the screens
 * use with the same shapes, applies the same `@wambito/core` rules, validates bodies with the same
 * zod schemas and fails with the same problem+json codes. Nothing leaves the page: no network, no
 * storage. A reload builds it again from the seed; `reset()` does the same in place.
 *
 * The account is laid over the last 3 months counted back from `now()` in the seed's time zone.
 * Ids come from a counter, not from randomness, so the same seed and clock give the same answers.
 */
export interface DemoBackend {
  fetch: typeof globalThis.fetch;
  /** Back to the seed, as a reload would. */
  reset(): void;
}

const pad = (n: number, width = 2) => String(n).padStart(width, "0");

/** A valid v4-shaped UUID from a counter: `00000000-0000-4000-8000-000000000001`, and so on. */
const uuidFrom = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

/** Major units to hundredths. Past months round to whole hundreds of pesos or to 5 cents. */
function cents(amount: number, currency: string, factor = 1): number {
  const scaled = amount * factor;
  if (currency === "COP") return Math.round(scaled / 100) * 100 * 100;
  return factor === 1 ? Math.round(scaled * 100) : Math.round(scaled * 20) * 5;
}

/** Writes the seed into the store, laid over the 3 months up to `now`. */
async function seedStore(
  store: FinanceStore,
  seed: DemoSeed,
  now: Date,
  newId: () => string,
): Promise<void> {
  const { profile } = seed;
  const today = todayIn(profile.timezone, now);
  const current = monthOf(today);
  const first = addMonths(current, -2);
  const since = `${firstDay(first)}T12:00:00.000Z`;

  await store.transaction(async (tx) => {
    const categoryIds = new Map<string, string>();
    for (const [index, c] of seed.categories.entries()) {
      const id = newId();
      categoryIds.set(c.key, id);
      await tx.put("category", id, {
        s: 1,
        name: c.name,
        kind: c.kind,
        icon: c.icon,
        color: c.color,
        sortOrder: index,
        archivedAt: null,
        systemKey: null,
        createdAt: since,
      });
    }
    const categoryId = (key: string) => {
      const id = categoryIds.get(key);
      if (!id) throw new Error(`Demo seed: unknown category "${key}"`);
      return id;
    };
    for (const c of seed.categories) {
      if (c.budget === null) continue;
      await tx.put("budget", newId(), {
        s: 1,
        categoryId: categoryId(c.key),
        amount: cents(c.budget, profile.currency),
        effectiveFrom: first,
      });
    }
    const rules: (RecordBodies["recurrence"] & { id: string })[] = [];
    for (const r of seed.recurrences) {
      const rule: RecordBodies["recurrence"] & { id: string } = {
        id: newId(),
        s: 1,
        name: r.name,
        amount: cents(r.amount, profile.currency),
        categoryId: categoryId(r.category),
        frequency: "monthly",
        dayOfMonth: r.dayOfMonth,
        monthOfYear: null,
        startDate: `${first}-${pad(r.dayOfMonth)}`,
        endDate: null,
        rev: 0,
        createdAt: since,
      };
      rules.push(rule);
      const { id, ...body } = rule;
      await tx.put("recurrence", id, body);
    }

    const todayDay = Number(today.slice(8));
    const lastSeedDay = Math.max(...seed.month.map((s) => s.day));
    for (const back of [2, 1, 0]) {
      const month = addMonths(current, -back);
      const factors = back === 0 ? null : (seed.pastMonths[back - 1] ?? {});
      type Entry = Omit<RecordBodies["transaction"], "createdAt">;
      const entries: Entry[] = [];
      const base = {
        s: 1 as const,
        currency: profile.currency,
        status: "paid" as const,
        note: null,
        accountId: null,
        needsReview: false,
        captureSource: null,
        capturedAt: null,
        captureMerchantKey: null,
      };
      for (const rule of rules) {
        for (const date of occurrences(rule, month)) {
          // This month only what is due by today is paid; the rest comes as pending on read.
          if (back === 0 && date > today) continue;
          entries.push({
            ...base,
            name: rule.name,
            amount: rule.amount,
            date,
            categoryId: rule.categoryId,
            recurrenceId: rule.id,
            occurrenceMonth: month,
            source: "recurrence",
          });
        }
      }
      for (const spend of seed.month) {
        // Early in the month the month's story is squeezed into the days so far: never in the future.
        const day =
          back > 0 || todayDay >= lastSeedDay
            ? spend.day
            : Math.max(1, Math.ceil((spend.day * todayDay) / lastSeedDay));
        entries.push({
          ...base,
          name: spend.name,
          amount: -cents(spend.amount, profile.currency, factors?.[spend.category] ?? 1),
          date: `${month}-${pad(day)}`,
          categoryId: categoryId(spend.category),
          recurrenceId: null,
          occurrenceMonth: null,
          source: "app",
        });
      }
      entries.sort((x, y) => (x.date < y.date ? -1 : x.date > y.date ? 1 : 0));
      for (const [index, entry] of entries.entries()) {
        const at = `${entry.date}T12:${pad(Math.floor(index / 60))}:${pad(index % 60)}.000Z`;
        await tx.put("transaction", newId(), { ...entry, createdAt: at });
      }
    }

    await tx.put("settings", newId(), {
      s: 1,
      name: null,
      currency: profile.currency,
      locale: profile.locale,
      timezone: profile.timezone,
      onboardingCompletedAt: since,
    });
  });
}

export function createDemoBackend(seed: DemoSeed, now: () => Date = () => new Date()): DemoBackend {
  function start() {
    const store = createMemoryStore();
    let counter = 1;
    const newId = () => uuidFrom(counter++);
    const backend = createLocalBackend({
      store,
      now,
      profile: { id: "demo-valentina", email: seed.profile.email, isAnonymous: false },
      unavailable: DEMO_UNAVAILABLE,
      newId,
    });
    // The clock is read now, as a reload would; the store fills in the background.
    const ready = seedStore(store, seed, now(), newId);
    ready.catch(() => undefined);
    return { backend, ready };
  }

  let current = start();

  return {
    fetch: (async (input, init) => {
      const { backend, ready } = current;
      await ready;
      return backend.fetch(input, init);
    }) as typeof globalThis.fetch,
    reset() {
      current = start();
    },
  };
}
