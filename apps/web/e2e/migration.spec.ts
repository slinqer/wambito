import { expect, type Page, test } from "@playwright/test";
import {
  clientIp,
  pinClock,
  psql,
  seedMigrateUser,
  setUpRecoveryKey,
  signInExisting,
} from "./helpers.ts";

/**
 * The switch day (E2E stage 5): the plain account `migrate-e2e` (migrate@wambito.test, in COP; the
 * stack's MIGRATION_OPEN_USER_IDS lists it by default) moves to encrypted from the web. Each test
 * makes the account again first (`seed:e2e-migrate` in the api container: an archived category
 * with transactions, budgets over several months, a yearly recurrence and a monthly one with a
 * dismissed month, a deleted transaction, a capture with its merchant rule), signs in by email
 * code and runs the flow: intro, the recovery key and its 4-character check, the copy, done.
 * - What the plain API answered before is what the vault answers after, on screen and route by
 *   route, and the server keeps no plaintext row of the account.
 * - A reload in the middle of the copy picks the move up and finishes it.
 */

const EMAIL = "migrate@wambito.test";
const USER_ID = "migrate-e2e";
/** The plaintext tables `finish` empties. */
const FINANCE_TABLES = [
  "transactions",
  "categories",
  "category_budgets",
  "recurrences",
  "merchant_categories",
  "accounts",
  "imports",
  "idempotency_keys",
];

test.describe.configure({ mode: "serial" });
test.use({
  locale: "es-ES",
  timezoneId: "Europe/Madrid",
  actionTimeout: 10_000,
  extraHTTPHeaders: async ({ extraHTTPHeaders }, use) =>
    use({ ...extraHTTPHeaders, "x-forwarded-for": clientIp() }),
});
// One seeded account for the whole file (its sign-in codes and its migration would cross between
// the projects running at once), so it runs on the desktop project only, as vault.spec.ts does.
test.skip(({ isMobile }) => isMobile, "one account to migrate per run, desktop only");

/** Pesos as the Spanish UI writes them ("$1.200.000"; whole pesos, the minus sign U+2212). */
const cop = (cents: number) =>
  new Intl.NumberFormat("es-CO", {
    style: "currency",
    currency: "COP",
    currencyDisplay: "narrowSymbol",
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })
    .format(cents / 100)
    .replace(/\$\s/, "$")
    .replaceAll("-", "−");

interface Summary {
  remaining: number;
  budgetTotal: number;
  categories: { categoryId: string; budget: number | null; remaining: number | null }[];
}
interface Category {
  id: string;
  name: string;
  archived: boolean;
}
interface Listed {
  items: { id: string; name: string; status: string; amount: number }[];
}

const MONTHS = ["2026-08", "2026-09", "2026-10"];
/** What the screens read, through `/api` (the plain API before, the vault's backend after). */
const READS = [
  ...MONTHS.map((m) => `/api/v1/summary?month=${m}`),
  ...MONTHS.map((m) => `/api/v1/transactions?month=${m}&limit=200`),
  "/api/v1/categories?includeArchived=true",
  "/api/v1/recurrences",
];

/** The plain API's answers, with the browser's session. */
async function readPlain(page: Page): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  for (const path of READS) {
    const response = await page.request.get(path);
    expect(response.status(), `${path}: ${await response.text()}`).toBe(200);
    out[path] = await response.json();
  }
  return out;
}

/**
 * A request to this tab's open vault (its local `/v1` backend), through the module the app itself
 * loaded from the dev server: the vault answers the screens in the browser, never over the network.
 */
type VaultModule = typeof import("../app/local/vault-session.ts");
type StoreModule = typeof import("../app/local/encrypted-store.ts");

async function vaultFetch(
  page: Page,
  path: string,
  method = "GET",
): Promise<{ status: number; body: unknown }> {
  return page.evaluate(
    async ({ path, method, userId, module }) => {
      const vault: VaultModule = await import(/* @vite-ignore */ module);
      // The tab's session is already open: the call hands it back without touching the keys.
      const session = await vault.openVaultSession({
        profile: { id: userId },
        keys: null,
        fresh: false,
      } as never);
      const response = await session.fetch(path, { method });
      const text = await response.text();
      return { status: response.status, body: text ? JSON.parse(text) : null };
    },
    { path, method, userId: USER_ID, module: "/app/local/vault-session.ts" },
  );
}

async function readVault(page: Page): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  for (const path of READS) {
    const { status, body } = await vaultFetch(page, path);
    expect(status, path).toBe(200);
    out[path] = body;
  }
  return out;
}

/**
 * Records straight from this browser's vault (its IndexedDB store, opened a second time and closed
 * again), for the fields no `/v1` answer carries: a capture's merchant key and time, and the
 * merchant records (the phone's merchant memory; the web's backend never reads them).
 */
async function vaultRecords(page: Page, transactionId: string) {
  return page.evaluate(
    async ({ userId, transactionId, module }) => {
      const { createEncryptedStore }: StoreModule = await import(/* @vite-ignore */ module);
      const store = await createEncryptedStore(userId);
      try {
        const tx = await store.get("transaction", transactionId);
        const merchants = await store.list("merchant");
        return { transaction: tx?.body ?? null, merchants: merchants.map((m) => m.body) };
      } finally {
        store.close();
      }
    },
    { userId: USER_ID, transactionId, module: "/app/local/encrypted-store.ts" },
  );
}

/** The fields a transaction keeps through the move (the vault adds none and drops `accountId`). */
const sameTransactions = (listed: Listed) =>
  listed.items
    .map(({ id, name, status, amount }) => ({ id, name, status, amount }))
    .sort((a, b) => a.id.localeCompare(b.id));

/** Signs the seeded account in; it lands on the migration's intro. */
async function signIn(page: Page) {
  await pinClock(page);
  await signInExisting(page, EMAIL);
  await expect(page).toHaveURL(/\/app$/);
  await expect(page.getByRole("heading", { name: "Protege tus datos" })).toBeVisible();
}

/** "Listo", then "Continuar" into the vault (the install offer, if any, is skipped). */
async function intoTheVault(page: Page) {
  await expect(page.getByRole("heading", { name: "Listo: tu cuenta está cifrada." })).toBeVisible({
    timeout: 30_000,
  });
  await page.getByRole("button", { name: "Continuar" }).click();
  const browserButton = page.getByRole("button", { name: "Continuar en el navegador" });
  const hero = page.getByRole("region", { name: "Te quedan este mes" });
  await expect(browserButton.or(hero)).toBeVisible({ timeout: 20_000 });
  if (await browserButton.isVisible()) await browserButton.click();
  await expect(page).toHaveURL(/\/app$/);
  await expect(hero).toBeVisible();
}

function expectNoPlaintextLeft() {
  for (const table of FINANCE_TABLES) {
    expect(psql(`select count(*) from ${table} where user_id = '${USER_ID}'`), table).toBe("0");
  }
  expect(psql(`select encryption from "user" where id = '${USER_ID}'`)).toBe("encrypted");
  expect(psql(`select migration_session_id is null from "user" where id = '${USER_ID}'`)).toBe("t");
}

test.beforeEach(() => {
  seedMigrateUser();
});

test("a plain account migrates and keeps everything", async ({ page }) => {
  test.setTimeout(120_000);
  await signIn(page);

  // Before: the plain API's figures (reading October also brings the yearly insurance's payment).
  const before = await readPlain(page);
  const october = before["/api/v1/summary?month=2026-10"] as Summary;
  const categories = before["/api/v1/categories?includeArchived=true"] as Category[];
  expect(categories.find((c) => c.name === "Viajes")?.archived).toBe(true);
  const octoberItems = (before["/api/v1/transactions?month=2026-10&limit=200"] as Listed).items;
  expect(octoberItems.map((t) => t.name)).not.toContain("Arriendo");
  expect(octoberItems.map((t) => t.name)).not.toContain("Taxi al aeropuerto");
  expect(octoberItems.map((t) => t.name)).toContain("Seguro del carro");
  const taxi = psql(
    `select id from transactions where user_id = '${USER_ID}' and name = 'Taxi al aeropuerto'`,
  );
  expect(taxi).toMatch(/^[0-9a-f-]{36}$/);
  // The capture, as the plain API lists it, and what only the database holds of it and its rule.
  type Captured = {
    id: string;
    note: string | null;
    source: string;
    captureSource: string | null;
    needsReview: boolean;
  };
  const capturedBefore = (octoberItems as unknown as Captured[]).find(
    (t) => t.source === "capture",
  );
  expect(capturedBefore?.captureSource).toBe("revolut");
  const capturedId = capturedBefore?.id ?? "";
  const [merchantKey, capturedAt] = psql(
    `select capture_merchant_key, to_char(captured_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') from transactions where id = '${capturedId}'`,
  ).split("|");
  expect(merchantKey).toBe("supermercado la esquina");
  const rule = psql(
    `select merchant_key || '|' || category_id from merchant_categories where user_id = '${USER_ID}'`,
  );
  const noted = (octoberItems as unknown as Captured[]).find((t) => t.note !== null);
  expect(noted?.note).toBe("Frutas para la semana");

  // The flow: intro, the key and its check, the copy, done.
  await page.getByRole("button", { name: "Empezar" }).click();
  await setUpRecoveryKey(page);
  await intoTheVault(page);

  // The server holds no plaintext of the account any more.
  expectNoPlaintextLeft();

  // Home: this month's figures and every budget row are the plain API's.
  const hero = page.getByRole("region", { name: "Te quedan este mes" });
  await expect(hero).toContainText(cop(october.remaining));
  await expect(hero.getByRole("meter")).toHaveAccessibleName(
    `Gastado ${cop(october.budgetTotal - october.remaining)} de ${cop(october.budgetTotal)}`,
  );
  const tab = page.getByRole("tabpanel", { name: "Categorías" });
  for (const row of october.categories) {
    const name = categories.find((c) => c.id === row.categoryId)?.name ?? "";
    if (row.remaining === null || row.budget === null) continue;
    await expect(tab.getByRole("button", { name: new RegExp(`^${name}`) })).toHaveAccessibleName(
      `${name} Quedan ${cop(row.remaining)}`,
    );
  }
  // The archived category is still archived: folded away, not among the month's rows.
  await expect(tab.getByRole("button", { name: /^Viajes/ })).toHaveCount(0);
  await expect(tab.getByRole("button", { name: "Archivadas (1)" })).toBeVisible();

  // The dismissed rent of October does not come back, and the deleted taxi stays deleted.
  const movements = page.getByRole("tabpanel", { name: "Movimientos" });
  await expect(movements.getByRole("button", { name: /^Fruver del barrio/ })).toBeVisible();
  await expect(movements.getByRole("button", { name: /^Arriendo/ })).toHaveCount(0);
  await expect(movements.getByRole("button", { name: /^Taxi al aeropuerto/ })).toHaveCount(0);

  // Route by route, the vault answers what the plain API did: every month's summary (the budget
  // history), the categories (archived included), the recurrences and the movements.
  const after = await readVault(page);
  for (const month of MONTHS) {
    const path = `/api/v1/summary?month=${month}`;
    expect(after[path], path).toEqual(before[path]);
    const list = `/api/v1/transactions?month=${month}&limit=200`;
    expect(sameTransactions(after[list] as Listed), list).toEqual(
      sameTransactions(before[list] as Listed),
    );
  }
  const pick = (cs: Category[]) =>
    cs
      .map(({ id, name, archived }) => ({ id, name, archived }))
      .sort((a, b) => a.id.localeCompare(b.id));
  expect(pick(after["/api/v1/categories?includeArchived=true"] as Category[])).toEqual(
    pick(categories),
  );
  type Rule = { id: string; name: string; amount: number; frequency: string };
  const rules = (rs: Rule[]) =>
    rs
      .map(({ id, name, amount, frequency }) => ({ id, name, amount, frequency }))
      .sort((a, b) => a.id.localeCompare(b.id));
  expect(rules(after["/api/v1/recurrences"] as Rule[])).toEqual(
    rules(before["/api/v1/recurrences"] as Rule[]),
  );

  // The capture keeps its source, merchant key and time, the note stays, and the merchant rule
  // is a merchant record with the same category.
  const listedAfter = (after["/api/v1/transactions?month=2026-10&limit=200"] as Listed)
    .items as unknown as Captured[];
  const pickCapture = ({ note, source, captureSource, needsReview }: Captured) => ({
    note,
    source,
    captureSource,
    needsReview,
  });
  const capturedAfter = listedAfter.find((t) => t.id === capturedId);
  expect(capturedAfter && pickCapture(capturedAfter)).toEqual(
    capturedBefore && pickCapture(capturedBefore),
  );
  expect(listedAfter.find((t) => t.id === noted?.id)?.note).toBe("Frutas para la semana");
  const records = await vaultRecords(page, capturedId);
  expect(records.transaction).toMatchObject({
    captureSource: "revolut",
    captureMerchantKey: merchantKey,
  });
  expect(
    new Date(String((records.transaction as { capturedAt: unknown }).capturedAt)).toISOString(),
  ).toBe(`${capturedAt}.000Z`);
  expect(
    records.merchants.map((m) => {
      const { merchantKey, categoryId } = m as { merchantKey: string; categoryId: string };
      return `${merchantKey}|${categoryId}`;
    }),
  ).toEqual([rule]);

  // Restoring the deleted taxi brings it back, under its own id.
  const restored = await vaultFetch(page, `/api/v1/transactions/${taxi}/restore`, "POST");
  expect(restored.status).toBeLessThan(300);
  await expect(movements.getByRole("button", { name: /^Taxi al aeropuerto/ })).toBeVisible();
});

test("a reload during copying resumes and finishes", async ({ page }) => {
  test.setTimeout(120_000);
  await signIn(page);
  const before = await readPlain(page);
  const october = before["/api/v1/summary?month=2026-10"] as Summary;

  // The first push is held, so the copy is caught midway; the reload drops it.
  let held = false;
  await page.route("**/api/v2/sync", async (route) => {
    if (route.request().method() !== "POST" || held) return route.fallback();
    held = true;
  });

  await page.getByRole("button", { name: "Empezar" }).click();
  await setUpRecoveryKey(page);
  await expect(page.getByRole("progressbar", { name: "Progreso del cifrado" })).toBeVisible();
  await expect.poll(() => held).toBe(true);
  expect(psql(`select encryption from "user" where id = '${USER_ID}'`)).toBe("migrating");
  // The data key as the server holds it before the reload: its wraps and links.
  const keys = () => ({
    recovery: psql(
      `select id || '|' || key_v || '|' || md5(wrapped) from key_wraps where user_id = '${USER_ID}' and kind = 'recovery'`,
    ),
    devices: psql(
      `select string_agg(id || '|' || key_v || '|' || md5(wrapped), ',' order by id) from key_wraps where user_id = '${USER_ID}' and kind = 'device'`,
    ),
    links: psql(`select count(*) from key_links where user_id = '${USER_ID}'`),
  });
  const keysBefore = keys();
  expect(keysBefore.recovery).toMatch(/^[0-9a-f-]{36}\|1\|[0-9a-f]{32}$/);
  expect(keysBefore.devices).toMatch(/^[0-9a-f-]{36}\|1\|[0-9a-f]{32}$/);

  await page.unrouteAll({ behavior: "ignoreErrors" });
  await page.reload();
  // The keys stayed in this browser: no second key, the copy starts over and finishes.
  await expect(page.getByRole("heading", { name: "Guarda tu clave de recuperación" })).toHaveCount(
    0,
  );
  await intoTheVault(page);
  expectNoPlaintextLeft();
  // The same data key: the very wraps (id, version, bytes) and no new link.
  expect(keys()).toEqual(keysBefore);
  await expect(page.getByRole("region", { name: "Te quedan este mes" })).toContainText(
    cop(october.remaining),
  );
  const after = await vaultFetch(page, "/api/v1/summary?month=2026-10");
  expect(after.body).toEqual(october);
});
