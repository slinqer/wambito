// Development and CI seed: the plain account the switch-day e2e migrates to encrypted
// (`apps/web/e2e/migration.spec.ts`). Resets the user `migrate-e2e` (migrate@wambito.test, email
// verified, onboarded, in COP, Spanish, Madrid) as `plain`, with every kind of row a real account
// has (the stage 5 plan's Review Focus 3):
// - an archived category ("Viajes") that still has transactions (August);
// - budgets over several months (Mercado from August, raised from October; Transporte from
//   September);
// - a yearly recurrence (car insurance, every 28 October) and a monthly one (rent on the 5th)
//   whose October occurrence the person dismissed (soft-deleted, pending, from the recurrence);
// - a soft-deleted transaction ("Taxi al aeropuerto");
// - a captured bank notification with a merchant key, and the merchant rule it taught.
// The user is deleted and made again, so nothing (sessions, finance rows, records, key wraps) is
// left from an earlier run, and its sign-in email throttle is cleared. The API opens the migration
// to it with MIGRATION_OPEN_USER_IDS=migrate-e2e (the root docker-compose.yml's default). All the
// data is invented. Run: pnpm --filter @wambito/api seed:e2e-migrate
import {
  accounts,
  categories,
  categoryBudgets,
  createDb,
  emailThrottle,
  merchantCategories,
  recurrences,
  transactions,
  user,
  withUser,
} from "@wambito/db";
import { eq, or } from "@wambito/db/orm";

const ID = "migrate-e2e";
const EMAIL = "migrate@wambito.test";
const CURRENCY = "COP";

/** COP pesos in integer cents (minor units). */
const pesos = (n: number) => n * 100;

const url = process.env.DATABASE_ADMIN_URL;
if (!url) throw new Error("DATABASE_ADMIN_URL is not set");
const { db, close } = createDb(url);

try {
  // The address is reserved for this account: a user that signed up with it (another id) goes too.
  await db.delete(user).where(or(eq(user.id, ID), eq(user.email, EMAIL)));
  await db.insert(user).values({
    id: ID,
    name: "Migrate",
    email: EMAIL,
    emailVerified: true,
    encryption: "plain",
    platform: "web",
    locale: "es",
    timezone: "Europe/Madrid",
    onboardingCompletedAt: new Date("2026-08-01T10:00:00Z"),
  });
  await db.delete(emailThrottle).where(eq(emailThrottle.email, EMAIL));

  await withUser(db, ID, async (tx) => {
    const [account] = await tx
      .insert(accounts)
      .values({ userId: ID, name: "Principal", currency: CURRENCY, isDefault: true })
      .returning({ id: accounts.id });
    const accountId = (account as { id: string }).id;

    const category = async (
      name: string,
      kind: "expense" | "income",
      icon: string,
      color: string,
      sortOrder: number,
      archivedAt: Date | null = null,
    ) => {
      const [row] = await tx
        .insert(categories)
        .values({ userId: ID, name, kind, icon, color, sortOrder, archivedAt })
        .returning({ id: categories.id });
      return (row as { id: string }).id;
    };
    const mercado = await category("Mercado", "expense", "🛒", "#3fa7ff", 0);
    const transporte = await category("Transporte", "expense", "🚌", "#ff9f43", 1);
    const hogar = await category("Hogar", "expense", "🏠", "#a66bff", 2);
    const viajes = await category(
      "Viajes",
      "expense",
      "✈️",
      "#2ec4b6",
      3,
      new Date("2026-09-10T09:00:00Z"),
    );
    const salario = await category("Salario", "income", "💼", "#2ecc71", 4);

    await tx.insert(categoryBudgets).values([
      { userId: ID, categoryId: mercado, amount: pesos(400_000), effectiveFrom: "2026-08-01" },
      { userId: ID, categoryId: mercado, amount: pesos(450_000), effectiveFrom: "2026-10-01" },
      { userId: ID, categoryId: transporte, amount: pesos(150_000), effectiveFrom: "2026-09-01" },
    ]);

    const [rent] = await tx
      .insert(recurrences)
      .values({
        userId: ID,
        accountId,
        categoryId: hogar,
        name: "Arriendo",
        amount: -pesos(1_200_000),
        frequency: "monthly",
        dayOfMonth: 5,
        startDate: "2026-08-05",
      })
      .returning({ id: recurrences.id });
    const rentId = (rent as { id: string }).id;
    const [insurance] = await tx
      .insert(recurrences)
      .values({
        userId: ID,
        accountId,
        categoryId: transporte,
        name: "Seguro del carro",
        amount: -pesos(98_000),
        frequency: "yearly",
        dayOfMonth: 28,
        monthOfYear: 10,
        startDate: "2025-10-28",
      })
      .returning({ id: recurrences.id });
    const insuranceId = (insurance as { id: string }).id;

    const base = { userId: ID, accountId, currency: CURRENCY } as const;
    await tx.insert(transactions).values([
      // The archived category's trip, in August.
      {
        ...base,
        categoryId: viajes,
        name: "Hotel en Cartagena",
        amount: -pesos(640_000),
        date: "2026-08-14",
        source: "web",
      },
      {
        ...base,
        categoryId: viajes,
        name: "Vuelo a Cartagena",
        amount: -pesos(380_000),
        date: "2026-08-12",
        source: "web",
      },
      // The rent: paid in August and September, October dismissed.
      {
        ...base,
        categoryId: hogar,
        name: "Arriendo",
        amount: -pesos(1_200_000),
        date: "2026-08-05",
        recurrenceId: rentId,
        occurrenceMonth: "2026-08-01",
        source: "recurrence",
      },
      {
        ...base,
        categoryId: hogar,
        name: "Arriendo",
        amount: -pesos(1_200_000),
        date: "2026-09-05",
        recurrenceId: rentId,
        occurrenceMonth: "2026-09-01",
        source: "recurrence",
      },
      {
        ...base,
        categoryId: hogar,
        name: "Arriendo",
        amount: -pesos(1_200_000),
        date: "2026-10-05",
        status: "pending",
        recurrenceId: rentId,
        occurrenceMonth: "2026-10-01",
        source: "recurrence",
        deletedAt: new Date("2026-10-02T08:00:00Z"),
      },
      // Last year's car insurance, paid.
      {
        ...base,
        categoryId: transporte,
        name: "Seguro del carro",
        amount: -pesos(98_000),
        date: "2025-10-28",
        recurrenceId: insuranceId,
        occurrenceMonth: "2025-10-01",
        source: "recurrence",
      },
      // September and October.
      {
        ...base,
        categoryId: salario,
        name: "Nómina septiembre",
        amount: pesos(4_800_000),
        date: "2026-09-30",
        source: "web",
      },
      {
        ...base,
        categoryId: mercado,
        name: "Plaza de mercado",
        amount: -pesos(86_000),
        date: "2026-09-20",
        source: "web",
      },
      {
        ...base,
        categoryId: mercado,
        name: "Fruver del barrio",
        amount: -pesos(54_000),
        date: "2026-10-09",
        source: "web",
        note: "Frutas para la semana",
      },
      {
        ...base,
        categoryId: transporte,
        name: "Recarga del bus",
        amount: -pesos(40_000),
        date: "2026-10-13",
        source: "app",
      },
      // A captured notification, confirmed, with the merchant it taught.
      {
        ...base,
        categoryId: mercado,
        name: "Supermercado La Esquina",
        amount: -pesos(132_500),
        date: "2026-10-17",
        source: "capture",
        captureSource: "revolut",
        capturedAt: new Date("2026-10-17T18:42:00Z"),
        captureMerchantKey: "supermercado la esquina",
      },
      // A deleted one.
      {
        ...base,
        categoryId: transporte,
        name: "Taxi al aeropuerto",
        amount: -pesos(65_000),
        date: "2026-10-15",
        source: "web",
        deletedAt: new Date("2026-10-16T07:30:00Z"),
      },
    ]);
    await tx
      .insert(merchantCategories)
      .values({ userId: ID, merchantKey: "supermercado la esquina", categoryId: mercado });
  });
  console.log(`Seeded the plain account to migrate ${EMAIL} (id ${ID}).`);
} finally {
  await close();
}
