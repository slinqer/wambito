import { serve } from "@hono/node-server";
import { createDb, runMigrations } from "@wambito/db";
import { createApp } from "./app.ts";
import { loadConfig } from "./config.ts";
import { type Mailer, ResendMailer, SmtpMailer } from "./mailer.ts";
import { scheduleGuestCleanup } from "./services/guest-cleanup.ts";
import { scheduleTombstonePurge } from "./services/sync.ts";

const config = loadConfig(process.env);
// Development applies migrations itself; elsewhere they are a separate step with the owner role
// (deploy/personal runs a `migrate` service), so this process never holds that credential.
if (config.NODE_ENV === "development" && config.DATABASE_ADMIN_URL) {
  await runMigrations(config.DATABASE_ADMIN_URL);
}

const mailer: Mailer = config.RESEND_API_KEY
  ? new ResendMailer(config.RESEND_API_KEY, config.MAIL_FROM)
  : new SmtpMailer(config.SMTP_URL ?? "", config.MAIL_FROM, {
      tlsInsecure: config.SMTP_TLS_INSECURE,
    });
const { db } = createDb(config.DATABASE_URL);
const pinned = config.E2E_NOW;
if (pinned) console.log(`E2E_NOW: the clock is pinned to ${pinned.toISOString()}`);
const app = createApp({ config, db, mailer, now: pinned ? () => new Date(pinned) : undefined });

serve({ fetch: app.fetch, port: config.PORT }, ({ port }) => {
  console.log(`Wambito API listening on http://localhost:${port}`);
});

// Guests idle for over 60 days are deleted once a day (spec §4.4). Always the real clock: the
// pinned E2E clock would misjudge real session times.
scheduleGuestCleanup({ db });
// Deleted records older than 180 days are purged once a day (spec 2026-11-08 section 5.1), on the
// real clock too.
scheduleTombstonePurge({ db });
