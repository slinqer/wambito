import { keyWraps } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

let t: TestApp;
beforeAll(async () => {
  t = await createTestApp();
});
afterAll(() => t?.stop());

interface Assistant {
  clientId: string;
  name: string;
  domain: string | null;
  scopes: string[];
  connectedAt: string;
  lastUsedAt: string | null;
}
const list = async (headers: { authorization: string }) => {
  const res = await t.request("GET", "/v1/me/assistants", { headers });
  expect(res.status).toBe(200);
  return ((await res.json()) as { items: Assistant[] }).items;
};

describe("connected assistants", () => {
  test("lists the assistants the person let in, with their domain and scopes", async () => {
    const { headers } = await t.signIn("list@wambito.test");
    expect(await list(headers)).toEqual([]);
    const { clientId } = await t.authorize("list@wambito.test", { headers });
    const [assistant, ...rest] = await list(headers);
    expect(rest).toEqual([]);
    expect(assistant).toMatchObject({
      clientId,
      name: "Claude",
      domain: "claude.ai",
      scopes: ["finance:read", "finance:write", "offline_access"],
    });
    expect(assistant?.lastUsedAt).not.toBeNull();
  });

  test("someone else's assistants are not listed", async () => {
    await t.authorize("owner@wambito.test");
    const { headers } = await t.signIn("stranger@wambito.test");
    expect(await list(headers)).toEqual([]);
  });

  test("revoking deletes the consent and its refresh tokens", async () => {
    const { headers } = await t.signIn("revoke@wambito.test");
    const tokens = await t.authorize("revoke@wambito.test", { headers });
    const res = await t.request("DELETE", `/v1/me/assistants/${tokens.clientId}`, { headers });
    expect(res.status).toBe(204);
    expect(await list(headers)).toEqual([]);
    const refresh = await t.tokenRequest({
      grant_type: "refresh_token",
      refresh_token: tokens.refreshToken,
      client_id: tokens.clientId,
    });
    expect(refresh.status).toBe(400);
    expect(((await refresh.json()) as { error: string }).error).toBe("invalid_grant");
  });

  test("revoking for another account than the signed-in one is 409 session_changed and removes nothing", async () => {
    const email = "revoke-switched@wambito.test";
    const { headers, userId } = await t.signIn(email);
    const tokens = await t.authorize(email, { headers });
    await t.admin.insert(keyWraps).values({
      userId,
      kind: "assistant",
      ref: tokens.clientId,
      keyV: 1,
      wrapped: Buffer.alloc(60, 1),
    });
    // a tab whose vault is another account's, while the cookie is this one's
    const switched = await t.request("DELETE", `/v1/me/assistants/${tokens.clientId}`, {
      headers: { ...headers, "x-wambito-user": "someone-else" },
    });
    expect(switched.status).toBe(409);
    expect(((await switched.json()) as { code: string }).code).toBe("session_changed");
    expect((await list(headers)).map((a) => a.clientId)).toEqual([tokens.clientId]);
    const wraps = await t.admin.select().from(keyWraps).where(eq(keyWraps.userId, userId));
    expect(wraps.map((row) => row.ref)).toEqual([tokens.clientId]);
    const refresh = await t.tokenRequest({
      grant_type: "refresh_token",
      refresh_token: tokens.refreshToken,
      client_id: tokens.clientId,
    });
    expect(refresh.status).toBe(200);

    const named = await t.request("DELETE", `/v1/me/assistants/${tokens.clientId}`, {
      headers: { ...headers, "x-wambito-user": userId },
    });
    expect(named.status).toBe(204);
    expect(await list(headers)).toEqual([]);
    expect(await t.admin.select().from(keyWraps).where(eq(keyWraps.userId, userId))).toEqual([]);
  });

  test("revoking an assistant deletes its wraps and only its own", async () => {
    const email = "revoke-wraps@wambito.test";
    const { headers, userId } = await t.signIn(email);
    const first = await t.authorize(email, { headers });
    const second = await t.authorize(email, { headers, scope: "finance:write" });
    const wrap = (ref: string) => ({
      userId,
      kind: "assistant",
      ref,
      keyV: 1,
      wrapped: Buffer.alloc(60, 1),
    });
    await t.admin.insert(keyWraps).values([wrap(first.clientId), wrap(second.clientId)]);
    const res = await t.request("DELETE", `/v1/me/assistants/${first.clientId}`, { headers });
    expect(res.status).toBe(204);
    const left = await t.admin.select().from(keyWraps).where(eq(keyWraps.userId, userId));
    expect(left.map((row) => row.ref)).toEqual([second.clientId]);
  });

  test("revoking someone else's assistant is a 404 and leaves it", async () => {
    const theirs = await t.authorize("victim@wambito.test");
    const { headers } = await t.signIn("attacker@wambito.test");
    const res = await t.request("DELETE", `/v1/me/assistants/${theirs.clientId}`, { headers });
    expect(res.status).toBe(404);
    const refresh = await t.tokenRequest({
      grant_type: "refresh_token",
      refresh_token: theirs.refreshToken,
      client_id: theirs.clientId,
    });
    expect(refresh.status).toBe(200);
  });

  test("a client_id that is a URL (CIMD) reaches the route, encoded", async () => {
    const { headers } = await t.signIn("cimd-revoke@wambito.test");
    const id = encodeURIComponent("https://claude.ai/oauth/mcp-oauth-client-metadata");
    const res = await t.request("DELETE", `/v1/me/assistants/${id}`, { headers });
    expect(res.status).toBe(404);
    expect(((await res.json()) as { detail?: string }).detail).toBe("Assistant not found");
  });
});
