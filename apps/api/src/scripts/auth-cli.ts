// Auth instance for the Better Auth CLI, which regenerates packages/db/src/schema/auth.ts:
//   pnpm --filter @wambito/api auth:generate
import { createAuth } from "../auth.ts";

export const auth = createAuth({
  config: {
    DATABASE_URL: "postgres://x@localhost/x",
    DATABASE_ADMIN_URL: "postgres://x@localhost/x",
    BETTER_AUTH_SECRET: "x".repeat(32),
    API_URL: "http://localhost:3000",
    WEB_URL: "http://localhost:5173",
    MAIL_FROM: "x@x",
    PORT: 3000,
    NODE_ENV: "test",
    CLIENT_IP_HEADER: "x-forwarded-for",
    GUEST_SIGNUP: true,
    TRUSTED_PROXIES: [],
    ADMIN_USER_IDS: [],
    E2E_PREVIEW_USER_IDS: [],
  },
  db: {} as never,
  mailer: { send: async () => {} },
});
