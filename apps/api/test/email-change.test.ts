import { createHash } from "node:crypto";
import { adminAudit, emailChange, session, user } from "@wambito/db";
import { count, eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { adminMail } from "../src/emails/admin.ts";
import { emailHash } from "../src/services/admin/audit.ts";
import { ADMIN_EMAIL, ADMIN_ID, seedAdmin, verifiedAdmin } from "./admin-helpers.ts";
import { createTestApp, type TestApp } from "./harness.ts";

const REASON = "Lost the mailbox; checked by video call";
const DAY_MS = 24 * 60 * 60 * 1000;

let t: TestApp;
let headers: { cookie: string };
let clock = new Date();
let seq = 0;

beforeAll(async () => {
  t = await createTestApp({ ADMIN_USER_IDS: [ADMIN_ID] }, { now: () => clock });
  const key = await seedAdmin(t);
  headers = await verifiedAdmin(t, key);
});
afterAll(() => t?.stop());

/** A person with an email, signed in (one session), in `locale`. */
async function person(locale = "es") {
  const email = `changer${++seq}@wambito.test`;
  const { userId } = await t.signIn(email);
  await t.admin.update(user).set({ locale }).where(eq(user.id, userId));
  return { userId, email };
}

const newAddress = () => `fresh${++seq}@wambito.test`;

const request = (userId: string, body: unknown) =>
  t.request("POST", `/v1/admin/users/${userId}/email-change`, { headers, body });

const confirm = (token: string, ip?: string) =>
  t.request("POST", "/v1/email-change/confirm", {
    body: { token },
    ...(ip ? { headers: { "x-forwarded-for": `${ip}, 10.0.0.1` } } : {}),
  });

const code = async (res: Response) => ((await res.json()) as { code: string }).code;

/** The token in the link mailed to `email`. */
function tokenMailedTo(email: string): string {
  const mail = t.mailer.lastTo(email);
  const match = /confirm-email\?token=([A-Za-z0-9_-]+)/.exec(mail?.text ?? "");
  if (!match?.[1]) throw new Error(`no link mailed to ${email}`);
  return match[1];
}

async function userRow(userId: string) {
  const [row] = await t.admin.select().from(user).where(eq(user.id, userId));
  return row;
}

async function pending(userId: string) {
  return t.admin.select().from(emailChange).where(eq(emailChange.userId, userId));
}

async function auditFor(userId: string) {
  return t.admin.select().from(adminAudit).where(eq(adminAudit.targetUserId, userId));
}

async function sessionsOf(userId: string) {
  const [row] = await t.admin
    .select({ n: count() })
    .from(session)
    .where(eq(session.userId, userId));
  return row?.n ?? 0;
}

/** A person with a requested change: returns the token mailed to the new address. */
async function requested(locale = "es") {
  const p = await person(locale);
  const to = newAddress();
  const res = await request(p.userId, { newEmail: to, reason: REASON });
  expect(res.status).toBe(204);
  return { ...p, to, token: tokenMailedTo(to) };
}

describe("request an email change", () => {
  test("mails a link to the new address; stores only the token's hash", async () => {
    const { userId, email } = await person("en");
    const to = newAddress();
    const res = await request(userId, { newEmail: to, reason: REASON });
    expect(res.status).toBe(204);

    const mail = t.mailer.lastTo(to);
    expect(mail?.subject).toBe(
      adminMail("email_change_link", "en", { webUrl: t.config.WEB_URL }).subject,
    );
    expect(mail?.text).toContain(`${t.config.WEB_URL}/confirm-email?token=`);
    expect(mail?.text).not.toContain(REASON);
    const token = tokenMailedTo(to);
    expect(Buffer.from(token, "base64url")).toHaveLength(32);

    const rows = await pending(userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.newEmail).toBe(to);
    expect(rows[0]?.createdBy).toBe(ADMIN_ID);
    expect(rows[0]?.tokenHash).toBe(createHash("sha256").update(token).digest("hex"));
    expect(JSON.stringify(rows[0])).not.toContain(token);
    const expires = rows[0]?.expiresAt?.getTime() ?? 0;
    expect(Math.abs(expires - (clock.getTime() + DAY_MS))).toBeLessThan(5000);

    const audit = await auditFor(userId);
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({
      adminUserId: ADMIN_ID,
      action: "email.change_requested",
      emailHash: emailHash(email),
      reason: REASON,
    });
    // Nothing changes until the person confirms.
    expect((await userRow(userId))?.email).toBe(email);
  });

  test("a second request replaces the pending one", async () => {
    const { userId, token } = await requested();
    const to = newAddress();
    expect((await request(userId, { newEmail: to, reason: REASON })).status).toBe(204);
    const rows = await pending(userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.newEmail).toBe(to);
    expect((await confirm(token)).status).toBe(410);
  });

  test("normalizes the new email before the taken check", async () => {
    const other = await person();
    const { userId } = await person();
    const sent = t.mailer.sent.length;
    const res = await request(userId, {
      newEmail: `  ${other.email.toUpperCase()} `,
      reason: REASON,
    });
    expect(res.status).toBe(409);
    expect(await code(res)).toBe("email_taken");
    expect(t.mailer.sent.length).toBe(sent);
    expect(await pending(userId)).toHaveLength(0);
    expect(await auditFor(userId)).toHaveLength(0);
  });

  test("stores the new email trimmed and lowercased", async () => {
    const { userId } = await person();
    const to = newAddress();
    const res = await request(userId, { newEmail: ` ${to.toUpperCase()} `, reason: REASON });
    expect(res.status).toBe(204);
    expect((await pending(userId))[0]?.newEmail).toBe(to);
    expect(t.mailer.lastTo(to)).toBeDefined();
  });

  test("a guest → 409 is_guest", async () => {
    const anon = await t.request("POST", "/auth/sign-in/anonymous");
    const { user: u } = (await anon.json()) as { user: { id: string } };
    const res = await request(u.id, { newEmail: newAddress(), reason: REASON });
    expect(res.status).toBe(409);
    expect(await code(res)).toBe("is_guest");
    expect(await pending(u.id)).toHaveLength(0);
  });

  test("an unknown user → 404 user_not_found", async () => {
    const res = await request("nobody", { newEmail: newAddress(), reason: REASON });
    expect(res.status).toBe(404);
    expect(await code(res)).toBe("user_not_found");
  });

  test("no reason → 422; not an email → 422", async () => {
    const { userId } = await person();
    expect((await request(userId, { newEmail: newAddress() })).status).toBe(422);
    expect((await request(userId, { newEmail: "not-an-email", reason: REASON })).status).toBe(422);
  });

  test("a new email under .invalid → 422, nothing written or sent", async () => {
    const { userId } = await person();
    for (const newEmail of ["someone@guest.wambito.invalid", "someone@example.invalid."]) {
      const sent = t.mailer.sent.length;
      const res = await request(userId, { newEmail, reason: REASON });
      expect(res.status, newEmail).toBe(422);
      expect(await code(res)).toBe("validation_failed");
      expect(t.mailer.sent.length).toBe(sent);
    }
    expect(await pending(userId)).toHaveLength(0);
    expect(await auditFor(userId)).toHaveLength(0);
  });

  test("with SIGN_IN_ALLOWLIST set, a new email outside it → 409, nothing written or sent", async () => {
    const { userId, email } = await person();
    const allowed = newAddress();
    const outside = newAddress();
    const saved = t.config.SIGN_IN_ALLOWLIST;
    t.config.SIGN_IN_ALLOWLIST = [ADMIN_EMAIL, email, allowed];
    try {
      const sent = t.mailer.sent.length;
      const res = await request(userId, { newEmail: outside, reason: REASON });
      expect(res.status).toBe(409);
      expect(await code(res)).toBe("sign_in_not_allowed");
      expect(t.mailer.sent.length).toBe(sent);
      expect(await pending(userId)).toHaveLength(0);
      expect(await auditFor(userId)).toHaveLength(0);

      // An address on the list still works, and the person can sign in with it afterwards.
      expect((await request(userId, { newEmail: allowed, reason: REASON })).status).toBe(204);
      expect((await confirm(tokenMailedTo(allowed))).status).toBe(204);
      expect((await t.signIn(allowed)).userId).toBe(userId);
    } finally {
      t.config.SIGN_IN_ALLOWLIST = saved;
    }
  });

  test("an address taken off the allowlist before the confirm → 409, nothing changed", async () => {
    const { userId, email } = await person();
    const to = newAddress();
    const saved = t.config.SIGN_IN_ALLOWLIST;
    t.config.SIGN_IN_ALLOWLIST = [ADMIN_EMAIL, email, to];
    try {
      expect((await request(userId, { newEmail: to, reason: REASON })).status).toBe(204);
      const token = tokenMailedTo(to);
      t.config.SIGN_IN_ALLOWLIST = [ADMIN_EMAIL, email];
      const res = await confirm(token);
      expect(res.status).toBe(409);
      expect(await code(res)).toBe("sign_in_not_allowed");
      expect((await userRow(userId))?.email).toBe(email);
      expect(await pending(userId)).toHaveLength(1);
    } finally {
      t.config.SIGN_IN_ALLOWLIST = saved;
    }
  });

  test("needs a verified admin: no session → 404", async () => {
    const { userId } = await person();
    const res = await t.request("POST", `/v1/admin/users/${userId}/email-change`, {
      body: { newEmail: newAddress(), reason: REASON },
    });
    expect(res.status).toBe(404);
  });
});

describe("confirm an email change", () => {
  test("changes the email, signs out everywhere, audits, notifies the old address", async () => {
    const { userId, email, to, token } = await requested("pt");
    await t.signIn(email);
    expect(await sessionsOf(userId)).toBe(2);
    await t.admin.update(user).set({ emailVerified: false }).where(eq(user.id, userId));

    const res = await confirm(token);
    expect(res.status).toBe(204);

    const row = await userRow(userId);
    expect(row?.email).toBe(to);
    expect(row?.emailVerified).toBe(true);
    expect(await sessionsOf(userId)).toBe(0);
    expect(await pending(userId)).toHaveLength(0);

    const audit = (await auditFor(userId)).filter((a) => a.action === "email.change_confirmed");
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({
      adminUserId: null,
      emailHash: emailHash(email),
      reason: null,
    });

    const notice = t.mailer.lastTo(email);
    expect(notice?.subject).toBe(
      adminMail("email_changed", "pt", { webUrl: t.config.WEB_URL }).subject,
    );
  });

  test("the person signs in with the new email afterwards", async () => {
    const { userId, to, token } = await requested();
    expect((await confirm(token)).status).toBe(204);
    const signed = await t.signIn(to);
    expect(signed.userId).toBe(userId);
  });

  test("a second confirm → 410 link_expired", async () => {
    const { token } = await requested();
    expect((await confirm(token)).status).toBe(204);
    const again = await confirm(token);
    expect(again.status).toBe(410);
    expect(await code(again)).toBe("link_expired");
  });

  test("an unknown token → 410 link_expired", async () => {
    const res = await confirm("bm90LWEtcmVhbC10b2tlbi1hdC1hbGwtbm90LW9uZQ");
    expect(res.status).toBe(410);
    expect(await code(res)).toBe("link_expired");
  });

  test("at 24 h + 1 s → 410, nothing changed", async () => {
    const { userId, email, token } = await requested();
    const start = clock;
    try {
      clock = new Date(start.getTime() + DAY_MS + 1000);
      const res = await confirm(token);
      expect(res.status).toBe(410);
      expect(await code(res)).toBe("link_expired");
      expect((await userRow(userId))?.email).toBe(email);
    } finally {
      clock = start;
    }
  });

  test("just before 24 h it still works", async () => {
    const { token } = await requested();
    const start = clock;
    try {
      clock = new Date(start.getTime() + DAY_MS - 60_000);
      expect((await confirm(token)).status).toBe(204);
    } finally {
      clock = start;
    }
  });

  test("new email taken meanwhile → 409 email_taken and nothing changed", async () => {
    const { userId, email, to, token } = await requested();
    const sent = t.mailer.sent.length;
    await t.signIn(to);
    const res = await confirm(token);
    expect(res.status).toBe(409);
    expect(await code(res)).toBe("email_taken");
    expect((await userRow(userId))?.email).toBe(email);
    expect(await sessionsOf(userId)).toBe(1);
    expect(
      (await auditFor(userId)).filter((a) => a.action === "email.change_confirmed"),
    ).toHaveLength(0);
    // Only the new account's sign-in code was mailed; no notice to the old address.
    expect(t.mailer.sent.slice(sent).filter((m) => m.to === email)).toHaveLength(0);
  });

  test("a link confirms once under concurrency", async () => {
    const { userId, token } = await requested();
    const results = await Promise.all([confirm(token), confirm(token)]);
    expect(results.map((r) => r.status).sort()).toEqual([204, 410]);
    expect(
      (await auditFor(userId)).filter((a) => a.action === "email.change_confirmed"),
    ).toHaveLength(1);
  });

  test("not a token → 422", async () => {
    const res = await t.request("POST", "/v1/email-change/confirm", { body: {} });
    expect(res.status).toBe(422);
  });

  test("is rate limited: 10 per 10 minutes per IP", async () => {
    const ip = "203.0.113.77";
    for (let i = 0; i < 10; i++) {
      expect((await confirm(`unknown-token-${i}`, ip)).status).toBe(410);
    }
    const limited = await confirm("unknown-token-10", ip);
    expect(limited.status).toBe(429);
    expect(await code(limited)).toBe("too_many_requests");
    // Another address is not affected.
    expect((await confirm("unknown-token-11", "203.0.113.78")).status).toBe(410);
  });
});
