import { afterAll, beforeAll, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

// A /v2 call may say which account it means (`x-wambito-user`): a tab whose cookie now belongs to
// someone else (signed in as another person in another tab) must not read or write that person's
// records with the old vault's keys. A different id is 409 `session_changed`, before anything else.

let t: TestApp;

beforeAll(async () => {
  t = await createTestApp();
});
afterAll(() => t?.stop());

const RECORD = "01890a5d-ac96-7a3e-8f4b-1c2d3e4f5a6b";
const pushOne = {
  changes: [
    {
      id: RECORD,
      type: "category",
      baseVersion: null,
      deleted: false,
      keyV: 1,
      encV: 1,
      body: "A".repeat(40),
    },
  ],
};

test("a session: the same id goes through, another id is 409 session_changed", async () => {
  const me = await t.signIn("expected-same@wambito.test");
  const same = await t.request("GET", "/v2/sync?since=0", {
    headers: { ...me.headers, "x-wambito-user": me.userId },
  });
  expect(same.status).toBe(200);
  const other = await t.request("GET", "/v2/sync?since=0", {
    headers: { ...me.headers, "x-wambito-user": "someone-else" },
  });
  expect(other.status).toBe(409);
  expect(await other.json()).toMatchObject({ code: "session_changed" });
});

test("no header: as before", async () => {
  const me = await t.signIn("expected-none@wambito.test");
  expect((await t.request("GET", "/v2/sync?since=0", { headers: me.headers })).status).toBe(200);
});

test("a write for another id changes nothing", async () => {
  const me = await t.signIn("expected-write@wambito.test");
  const res = await t.request("POST", "/v2/sync", {
    headers: { ...me.headers, "x-wambito-user": "someone-else" },
    body: pushOne,
  });
  expect(res.status).toBe(409);
  const pulled = (await (
    await t.request("GET", "/v2/sync?since=0", { headers: me.headers })
  ).json()) as { records: unknown[] };
  expect(pulled.records).toEqual([]);
});

test("a cookie session and /v2/keys are guarded too", async () => {
  const me = await t.signInCookie("expected-cookie@wambito.test");
  const res = await t.request("GET", "/v2/keys", {
    headers: { ...me.headers, "x-wambito-user": "someone-else" },
  });
  expect(res.status).toBe(409);
  expect(await res.json()).toMatchObject({ code: "session_changed" });
  const ok = await t.request("GET", "/v2/keys", {
    headers: { ...me.headers, "x-wambito-user": me.userId },
  });
  expect(ok.status).toBe(200);
});

test("an assistant's token is guarded too", async () => {
  const me = await t.signIn("expected-token@wambito.test");
  const { accessToken } = await t.authorize("expected-token@wambito.test", {
    headers: me.headers,
  });
  const auth = { authorization: `Bearer ${accessToken}` };
  const other = await t.request("GET", "/v2/sync?since=0", {
    headers: { ...auth, "x-wambito-user": "someone-else" },
  });
  expect(other.status).toBe(409);
  expect(await other.json()).toMatchObject({ code: "session_changed" });
  const same = await t.request("GET", "/v2/sync?since=0", {
    headers: { ...auth, "x-wambito-user": me.userId },
  });
  expect(same.status).toBe(200);
});
