// Development and CI seed: the encrypted-preview account the vault e2e signs in with. Resets the
// user `preview-e2e` (preview@wambito.test, email verified, not onboarded) to the state of a new
// sign-up before the first sign-in: the user is deleted and made again, so everything it owned
// (sessions, /v1 finance rows, /v2 records, key wraps, pairing requests) is gone, and its sign-in
// email throttle is cleared. Unlike seed-admin it gives the account no default account or
// categories: a preview account keeps its finances as records, which the browser creates. The API
// treats it as a preview account with E2E_PREVIEW_USER_IDS=preview-e2e (the root
// docker-compose.yml's default). Idempotent: every run starts the account over.
// Run: pnpm --filter @wambito/api seed:e2e-preview
import { createDb, emailThrottle, user } from "@wambito/db";
import { eq, or } from "@wambito/db/orm";

const ID = "preview-e2e";
const EMAIL = "preview@wambito.test";

const url = process.env.DATABASE_ADMIN_URL;
if (!url) throw new Error("DATABASE_ADMIN_URL is not set");
const { db, close } = createDb(url);

try {
  // The address is reserved for this account: a user that signed up with it (another id) goes too.
  await db.delete(user).where(or(eq(user.id, ID), eq(user.email, EMAIL)));
  await db.insert(user).values({
    id: ID,
    name: "Preview",
    email: EMAIL,
    emailVerified: true,
    locale: "es",
  });
  await db.delete(emailThrottle).where(eq(emailThrottle.email, EMAIL));
  console.log(`Seeded the preview account ${EMAIL} (id ${ID}).`);
} finally {
  await close();
}
