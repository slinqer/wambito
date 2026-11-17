import {
  adminAudit,
  emailThrottle,
  keyWraps,
  oauthAccessToken,
  oauthConsent,
  oauthRefreshToken,
  passkey,
  session,
  user,
} from "@wambito/db";
import { count, eq } from "@wambito/db/orm";
import { afterAll, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { adminMail } from "../src/emails/admin.ts";
import { emailHash, recordAudit } from "../src/services/admin/audit.ts";
import { ADMIN_ID, seedAdmin, verifiedAdmin } from "./admin-helpers.ts";
import { createTestApp, type TestApp } from "./harness.ts";

// A pass-through spy, so a test can make the audit write fail and see the action roll back.
vi.mock("../src/services/admin/audit.ts", async (importOriginal) => {
  const original = await importOriginal<typeof import("../src/services/admin/audit.ts")>();
  return { ...original, recordAudit: vi.fn(original.recordAudit) };
});

const REASON = "Asked by the person in ticket 42";

let t: TestApp;
let headers: { cookie: string };
let seq = 0;

beforeAll(async () => {
  t = await createTestApp({ ADMIN_USER_IDS: [ADMIN_ID] });
  const key = await seedAdmin(t);
  headers = await verifiedAdmin(t, key);
});
afterAll(() => t?.stop());
beforeEach(() => {
  vi.mocked(recordAudit).mockClear();
});

/** A person with an email, signed in (one session), in `locale`. */
async function person(locale = "es") {
  const email = `person${++seq}@wambito.test`;
  const { userId } = await t.signIn(email);
  await t.admin.update(user).set({ locale }).where(eq(user.id, userId));
  return { userId, email };
}

/** A guest: a placeholder email under guest.wambito.invalid, one session. */
async function guest() {
  const res = await t.request("POST", "/auth/sign-in/anonymous");
  expect(res.status).toBe(200);
  const { user: u } = (await res.json()) as { user: { id: string } };
  return u.id;
}

const call = (method: string, path: string, body: unknown) =>
  t.request(method, path, { headers, body });

async function auditFor(targetUserId: string) {
  return t.admin.select().from(adminAudit).where(eq(adminAudit.targetUserId, targetUserId));
}

async function sessionsOf(userId: string) {
  const [row] = await t.admin
    .select({ n: count() })
    .from(session)
    .where(eq(session.userId, userId));
  return row?.n ?? 0;
}

async function userRow(userId: string) {
  const [row] = await t.admin.select().from(user).where(eq(user.id, userId));
  return row;
}

const code = async (res: Response) => ((await res.json()) as { code: string }).code;

/** Makes the next audit write throw, inside the action's transaction. */
function failAudit() {
  vi.mocked(recordAudit).mockRejectedValueOnce(new Error("audit write failed"));
}

function expectMail(email: string, kind: Parameters<typeof adminMail>[0], locale: string) {
  const mail = t.mailer.lastTo(email);
  expect(mail?.subject).toBe(adminMail(kind, locale, { webUrl: t.config.WEB_URL }).subject);
  expect(mail?.text).not.toContain(REASON);
  expect(mail?.html).not.toContain(REASON);
}

describe("delete an account", () => {
  test("deletes it, writes one audit row with the email hash, mails the person", async () => {
    const { userId, email } = await person("en");
    await t.admin.update(user).set({ email: email.toUpperCase() }).where(eq(user.id, userId));
    const res = await call("DELETE", `/v1/admin/users/${userId}`, {
      reason: REASON,
      confirm: ` ${email} `,
    });
    expect(res.status).toBe(204);
    expect(await userRow(userId)).toBeUndefined();
    const rows = await auditFor(userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      adminUserId: ADMIN_ID,
      action: "account.delete",
      targetUserId: userId,
      reason: REASON,
      emailHash: emailHash(email),
      detail: null,
    });
    const mail = t.mailer.lastTo(email.toUpperCase());
    expect(mail?.subject).toBe(
      adminMail("account_deleted", "en", { webUrl: t.config.WEB_URL }).subject,
    );
  });

  test("a confirm that does not match → 400, nothing deleted", async () => {
    const { userId } = await person();
    const res = await call("DELETE", `/v1/admin/users/${userId}`, {
      reason: REASON,
      confirm: "someone-else@wambito.test",
    });
    expect(res.status).toBe(400);
    expect(await userRow(userId)).toBeDefined();
    expect(await auditFor(userId)).toHaveLength(0);
  });

  test("deleting a guest sends no email; it confirms by id", async () => {
    const id = await guest();
    const sent = t.mailer.sent.length;
    const res = await call("DELETE", `/v1/admin/users/${id}`, { reason: REASON, confirm: id });
    expect(res.status).toBe(204);
    expect(await userRow(id)).toBeUndefined();
    expect(t.mailer.sent.length).toBe(sent);
    expect(await auditFor(id)).toHaveLength(1);
  });

  test("a guest's placeholder email does not confirm", async () => {
    const id = await guest();
    const row = await userRow(id);
    const res = await call("DELETE", `/v1/admin/users/${id}`, {
      reason: REASON,
      confirm: row?.email,
    });
    expect(res.status).toBe(400);
  });

  test("their own account → 409 cannot_target_self", async () => {
    const res = await call("DELETE", `/v1/admin/users/${ADMIN_ID}`, {
      reason: REASON,
      confirm: ADMIN_ID,
    });
    expect(res.status).toBe(409);
    expect(await code(res)).toBe("cannot_target_self");
    expect(await userRow(ADMIN_ID)).toBeDefined();
  });

  test("an unknown user → 404 user_not_found", async () => {
    const res = await call("DELETE", "/v1/admin/users/nobody", { reason: REASON, confirm: "x" });
    expect(res.status).toBe(404);
    expect(await code(res)).toBe("user_not_found");
  });

  test("a forced failure leaves the account in place and sends nothing", async () => {
    const { userId, email } = await person();
    const sent = t.mailer.sent.length;
    failAudit();
    const res = await call("DELETE", `/v1/admin/users/${userId}`, {
      reason: REASON,
      confirm: email,
    });
    expect(res.status).toBe(500);
    expect(await userRow(userId)).toBeDefined();
    expect(t.mailer.sent.length).toBe(sent);
  });
});

describe("sign out everywhere", () => {
  test("deletes every session, audits, mails", async () => {
    const { userId, email } = await person("it");
    await t.signIn(email);
    expect(await sessionsOf(userId)).toBe(2);
    const res = await call("POST", `/v1/admin/users/${userId}/sessions/revoke`, { reason: REASON });
    expect(res.status).toBe(204);
    expect(await sessionsOf(userId)).toBe(0);
    const rows = await auditFor(userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      action: "sessions.revoke",
      reason: REASON,
      emailHash: null,
      detail: null,
    });
    expectMail(email, "sessions_revoked", "it");
  });

  test("a forced failure keeps the sessions", async () => {
    const { userId } = await person();
    failAudit();
    const res = await call("POST", `/v1/admin/users/${userId}/sessions/revoke`, { reason: REASON });
    expect(res.status).toBe(500);
    expect(await sessionsOf(userId)).toBe(1);
  });

  test("a guest's sessions go, and no email is sent", async () => {
    const id = await guest();
    const sent = t.mailer.sent.length;
    const res = await call("POST", `/v1/admin/users/${id}/sessions/revoke`, { reason: REASON });
    expect(res.status).toBe(204);
    expect(await sessionsOf(id)).toBe(0);
    expect(t.mailer.sent.length).toBe(sent);
  });

  test("an unknown user → 404 user_not_found", async () => {
    const res = await call("POST", "/v1/admin/users/nobody/sessions/revoke", { reason: REASON });
    expect(res.status).toBe(404);
    expect(await code(res)).toBe("user_not_found");
  });
});

describe("revoke an assistant", () => {
  test("deletes its consent and tokens, audits with the clientId, mails its name", async () => {
    const { userId, email } = await person("pt");
    const { clientId } = await t.authorize(email);
    const res = await call("DELETE", `/v1/admin/users/${userId}/assistants/${clientId}`, {
      reason: REASON,
    });
    expect(res.status).toBe(204);
    for (const table of [oauthConsent, oauthAccessToken, oauthRefreshToken]) {
      const left = await t.admin.select().from(table).where(eq(table.userId, userId));
      expect(left).toHaveLength(0);
    }
    const rows = await auditFor(userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      action: "assistant.revoke",
      reason: REASON,
      emailHash: null,
      detail: { clientId },
    });
    const mail = t.mailer.lastTo(email);
    expect(mail?.subject).toBe(
      adminMail("assistant_revoked", "pt", { webUrl: t.config.WEB_URL, assistant: "Claude" })
        .subject,
    );
    expect(mail?.text).toContain("Claude");
  });

  test("an assistant the person has not connected → 404, nothing audited", async () => {
    const { userId } = await person();
    const clientId = await t.registerAssistant();
    const res = await call("DELETE", `/v1/admin/users/${userId}/assistants/${clientId}`, {
      reason: REASON,
    });
    expect(res.status).toBe(404);
    expect(await auditFor(userId)).toHaveLength(0);
  });

  test("a forced failure keeps the consent", async () => {
    const { userId, email } = await person();
    const { clientId } = await t.authorize(email);
    failAudit();
    const res = await call("DELETE", `/v1/admin/users/${userId}/assistants/${clientId}`, {
      reason: REASON,
    });
    expect(res.status).toBe(500);
    const left = await t.admin.select().from(oauthConsent).where(eq(oauthConsent.userId, userId));
    expect(left).toHaveLength(1);
  });
});

describe("remove a passkey", () => {
  async function addPasskey(userId: string, name: string | null = "Laptop") {
    const id = `pk-${++seq}`;
    await t.admin.insert(passkey).values({
      id,
      name,
      publicKey: "x",
      userId,
      credentialID: `cred-${id}`,
      counter: 0,
      deviceType: "multiDevice",
      backedUp: true,
    });
    return id;
  }

  test("deletes that passkey only, audits with the passkeyId, mails its name", async () => {
    const { userId, email } = await person("en");
    const id = await addPasskey(userId);
    const other = await addPasskey(userId, "Phone");
    const res = await call("DELETE", `/v1/admin/users/${userId}/passkeys/${id}`, {
      reason: REASON,
    });
    expect(res.status).toBe(204);
    const left = await t.admin.select().from(passkey).where(eq(passkey.userId, userId));
    expect(left.map((p) => p.id)).toEqual([other]);
    const rows = await auditFor(userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      action: "passkey.remove",
      reason: REASON,
      emailHash: null,
      detail: { passkeyId: id },
    });
    const mail = t.mailer.lastTo(email);
    expect(mail?.subject).toBe(
      adminMail("passkey_removed", "en", { webUrl: t.config.WEB_URL, passkey: "Laptop" }).subject,
    );
    expect(mail?.text).toContain("Laptop");
  });

  test("another person's passkey → 404, kept", async () => {
    const a = await person();
    const b = await person();
    const id = await addPasskey(b.userId);
    const res = await call("DELETE", `/v1/admin/users/${a.userId}/passkeys/${id}`, {
      reason: REASON,
    });
    expect(res.status).toBe(404);
    expect(await t.admin.select().from(passkey).where(eq(passkey.id, id))).toHaveLength(1);
  });

  test("a forced failure keeps the passkey", async () => {
    const { userId } = await person();
    const id = await addPasskey(userId);
    failAudit();
    const res = await call("DELETE", `/v1/admin/users/${userId}/passkeys/${id}`, {
      reason: REASON,
    });
    expect(res.status).toBe(500);
    expect(await t.admin.select().from(passkey).where(eq(passkey.id, id))).toHaveLength(1);
  });
});

describe("suspend", () => {
  test("sets suspendedAt, signs out, revokes every assistant, audits, mails", async () => {
    const { userId, email } = await person("es");
    await t.authorize(email);
    await t.authorize(email);
    const res = await call("POST", `/v1/admin/users/${userId}/suspend`, { reason: REASON });
    expect(res.status).toBe(204);
    expect((await userRow(userId))?.suspendedAt).toBeInstanceOf(Date);
    expect(await sessionsOf(userId)).toBe(0);
    for (const table of [oauthConsent, oauthAccessToken, oauthRefreshToken]) {
      const left = await t.admin.select().from(table).where(eq(table.userId, userId));
      expect(left).toHaveLength(0);
    }
    const rows = await auditFor(userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      action: "account.suspend",
      reason: REASON,
      emailHash: null,
      detail: null,
    });
    expectMail(email, "account_suspended", "es");
  });

  test("suspending deletes the assistants' key wraps", async () => {
    const { userId, email } = await person();
    const { clientId } = await t.authorize(email);
    await t.admin
      .insert(keyWraps)
      .values({ userId, kind: "assistant", ref: clientId, keyV: 1, wrapped: Buffer.alloc(60, 1) });
    const res = await call("POST", `/v1/admin/users/${userId}/suspend`, { reason: REASON });
    expect(res.status).toBe(204);
    expect(await t.admin.select().from(keyWraps).where(eq(keyWraps.userId, userId))).toEqual([]);
  });

  test("their own account → 409 cannot_target_self", async () => {
    const res = await call("POST", `/v1/admin/users/${ADMIN_ID}/suspend`, { reason: REASON });
    expect(res.status).toBe(409);
    expect(await code(res)).toBe("cannot_target_self");
    expect((await userRow(ADMIN_ID))?.suspendedAt).toBeNull();
  });

  test("a forced failure leaves the account active, signed in and connected", async () => {
    const { userId, email } = await person();
    await t.authorize(email);
    const before = await sessionsOf(userId);
    failAudit();
    const res = await call("POST", `/v1/admin/users/${userId}/suspend`, { reason: REASON });
    expect(res.status).toBe(500);
    expect((await userRow(userId))?.suspendedAt).toBeNull();
    expect(await sessionsOf(userId)).toBe(before);
    const left = await t.admin.select().from(oauthConsent).where(eq(oauthConsent.userId, userId));
    expect(left).toHaveLength(1);
  });

  test("suspending twice sends one email and writes one audit row; the second is a no-op", async () => {
    const { userId, email } = await person();
    const sent = t.mailer.sent.length;
    expect(
      (await call("POST", `/v1/admin/users/${userId}/suspend`, { reason: REASON })).status,
    ).toBe(204);
    const first = (await userRow(userId))?.suspendedAt;
    expect(
      (await call("POST", `/v1/admin/users/${userId}/suspend`, { reason: REASON })).status,
    ).toBe(204);
    expect((await userRow(userId))?.suspendedAt).toEqual(first);
    expect(await auditFor(userId)).toHaveLength(1);
    expect(t.mailer.sent.slice(sent).filter((m) => m.to === email)).toHaveLength(1);
  });

  test("an unknown user → 404 user_not_found", async () => {
    const res = await call("POST", "/v1/admin/users/nobody/suspend", { reason: REASON });
    expect(res.status).toBe(404);
    expect(await code(res)).toBe("user_not_found");
  });
});

describe("reactivate", () => {
  test("clears suspendedAt, audits, mails", async () => {
    const { userId, email } = await person("en");
    await t.admin.update(user).set({ suspendedAt: new Date() }).where(eq(user.id, userId));
    const res = await call("POST", `/v1/admin/users/${userId}/reactivate`, { reason: REASON });
    expect(res.status).toBe(204);
    expect((await userRow(userId))?.suspendedAt).toBeNull();
    const rows = await auditFor(userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ action: "account.reactivate", reason: REASON, detail: null });
    expectMail(email, "account_reactivated", "en");
  });

  test("an account that is not suspended: 204, no audit row, no email", async () => {
    const { userId, email } = await person();
    const sent = t.mailer.sent.length;
    const res = await call("POST", `/v1/admin/users/${userId}/reactivate`, { reason: REASON });
    expect(res.status).toBe(204);
    expect((await userRow(userId))?.suspendedAt).toBeNull();
    expect(await auditFor(userId)).toHaveLength(0);
    expect(t.mailer.sent.slice(sent).filter((m) => m.to === email)).toHaveLength(0);
  });

  test("an unknown user → 404 user_not_found", async () => {
    const res = await call("POST", "/v1/admin/users/nobody/reactivate", { reason: REASON });
    expect(res.status).toBe(404);
    expect(await code(res)).toBe("user_not_found");
  });

  test("a forced failure leaves the account suspended", async () => {
    const { userId } = await person();
    await t.admin.update(user).set({ suspendedAt: new Date() }).where(eq(user.id, userId));
    failAudit();
    const res = await call("POST", `/v1/admin/users/${userId}/reactivate`, { reason: REASON });
    expect(res.status).toBe(500);
    expect((await userRow(userId))?.suspendedAt).toBeInstanceOf(Date);
  });
});

describe("every action", () => {
  test("a missing or blank reason → 422, nothing done", async () => {
    const { userId, email } = await person();
    const paths: [string, string, Record<string, unknown>][] = [
      ["DELETE", `/v1/admin/users/${userId}`, { confirm: email }],
      ["POST", `/v1/admin/users/${userId}/sessions/revoke`, {}],
      ["DELETE", `/v1/admin/users/${userId}/assistants/c1`, {}],
      ["DELETE", `/v1/admin/users/${userId}/passkeys/p1`, {}],
      ["POST", `/v1/admin/users/${userId}/suspend`, {}],
      ["POST", `/v1/admin/users/${userId}/reactivate`, {}],
    ];
    for (const [method, path, body] of paths) {
      expect((await call(method, path, body)).status).toBe(422);
      expect((await call(method, path, { ...body, reason: "   " })).status).toBe(422);
      expect((await call(method, path, { ...body, reason: "x".repeat(301) })).status).toBe(422);
    }
    expect(await userRow(userId)).toBeDefined();
    expect(await sessionsOf(userId)).toBe(1);
    expect(await auditFor(userId)).toHaveLength(0);
  });

  test("a failed email is logged and does not undo the action", async () => {
    const { userId } = await person();
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const send = vi.spyOn(t.mailer, "send").mockRejectedValueOnce(new Error("smtp down"));
    const res = await call("POST", `/v1/admin/users/${userId}/sessions/revoke`, { reason: REASON });
    expect(res.status).toBe(204);
    expect(await sessionsOf(userId)).toBe(0);
    expect(await auditFor(userId)).toHaveLength(1);
    expect(error).toHaveBeenCalled();
    send.mockRestore();
    error.mockRestore();
  });

  test("without verification → 401", async () => {
    const { userId } = await person();
    await t.admin.delete(emailThrottle);
    const { headers: plain } = await t.signInCookie("admin@wambito.test");
    const res = await t.request("POST", `/v1/admin/users/${userId}/suspend`, {
      headers: plain,
      body: { reason: REASON },
    });
    expect(res.status).toBe(401);
  });
});
