// Development and CI seed: a plain user for the web e2e, which runs with NEW_USERS_ENCRYPTED on
// (every new sign-up is born encrypted). Inserts a user with the given email as a plain web
// sign-up leaves it before onboarding: email verified, `encryption: 'plain'`, platform `web`, the
// default time zone and language, not onboarded, and the starter data the user-create hook in
// auth.ts gives a plain web sign-up (`giveStarterData`: "Main" in EUR and the suggested
// categories, named in `locale`, the language the sign-up page would have sent). The e2e then
// signs it in by email. Idempotent: an existing email is left as it is.
// Run: pnpm --filter @wambito/api seed:e2e-plain-user <email> [es|en|it|pt]
import { randomBytes } from "node:crypto";
import type { SuggestionLocale } from "@wambito/core";
import { createDb, user } from "@wambito/db";
import { giveStarterData } from "../services/starter-data.ts";

const LOCALES: readonly SuggestionLocale[] = ["es", "en", "it", "pt"];

const [email, locale = "es"] = process.argv.slice(2);
if (!email || !email.includes("@")) {
  throw new Error("Usage: seed:e2e-plain-user <email> [es|en|it|pt]");
}
if (!LOCALES.includes(locale as SuggestionLocale)) {
  throw new Error(`Unknown language "${locale}": one of ${LOCALES.join(", ")}`);
}

const url = process.env.DATABASE_ADMIN_URL;
if (!url) throw new Error("DATABASE_ADMIN_URL is not set");
const { db, close } = createDb(url);

try {
  const address = email.toLowerCase();
  const [created] = await db
    .insert(user)
    .values({
      id: randomBytes(16).toString("hex"),
      name: "",
      email: address,
      emailVerified: true,
      encryption: "plain",
      platform: "web",
    })
    .onConflictDoNothing({ target: user.email })
    .returning({ id: user.id });
  if (created) {
    await giveStarterData(db, created.id, {
      currency: "EUR",
      locale: locale as SuggestionLocale,
    });
    console.log(`Seeded the plain user ${address} (id ${created.id}).`);
  } else {
    console.log(`The user ${address} already exists: left as it is.`);
  }
} finally {
  await close();
}
