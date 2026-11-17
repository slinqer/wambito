import { randomBytes } from "node:crypto";
import { oauthConsent } from "@wambito/db";
import { and, eq, sql } from "@wambito/db/orm";
import { compactDecrypt, decodeProtectedHeader } from "jose";
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from "vitest";
import { forgetPendingSecrets } from "../src/http/assistant-secret.ts";
import { ASSISTANT_REDIRECT, createTestApp, newAssistantSecret, type TestApp } from "./harness.ts";

// The assistant secret `S` (spec 2026-11-16 §4): posted as `wk` with the consent of an encrypted
// account, it rides the refresh token (`<token>.<S>`) and every access token (the `wk` claim, a
// JWE only the MCP opens), and is never stored or logged.

let t: TestApp;
let publicJwk: string | undefined;

beforeAll(async () => {
  t = await createTestApp({ E2E_PREVIEW_USER_IDS: [] });
  publicJwk = t.config.MCP_WK_PUBLIC_KEY;
});
afterAll(() => t?.stop());
afterEach(() => {
  t.config.MCP_WK_PUBLIC_KEY = publicJwk;
  vi.restoreAllMocks();
});

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
const payloadOf = (jwt: string) =>
  JSON.parse(Buffer.from(jwt.split(".")[1] ?? "", "base64url").toString()) as Record<
    string,
    unknown
  >;
const newSecret = newAssistantSecret;

/** Signs `email` in and puts the account in the encryption preview. */
async function encryptedUser(email: string) {
  const signed = await t.signIn(email);
  t.config.E2E_PREVIEW_USER_IDS.push(signed.userId);
  return signed;
}

async function openWk(accessToken: string): Promise<string> {
  const wk = payloadOf(accessToken).wk;
  if (typeof wk !== "string") throw new Error("no wk claim");
  expect(decodeProtectedHeader(wk)).toMatchObject({ alg: "ECDH-ES", enc: "A256GCM" });
  const { plaintext } = await compactDecrypt(wk, t.wkPrivateKey);
  return new TextDecoder().decode(plaintext);
}

async function refresh(refreshToken: string, clientId: string) {
  return t.tokenRequest({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: clientId,
  });
}

/** Connects, then refreshes three times: every token pair it saw. */
async function connectAndRefresh(email: string, S: string) {
  const { headers } = await encryptedUser(email);
  const first = await t.connectAssistant(email, { headers, wk: S });
  const pairs = [first];
  for (let i = 0; i < 3; i++) {
    const last = pairs[pairs.length - 1];
    if (!last) throw new Error("no tokens");
    const res = await refresh(last.refreshToken, first.clientId);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { access_token: string; refresh_token: string };
    pairs.push({
      accessToken: body.access_token,
      refreshToken: body.refresh_token,
      clientId: first.clientId,
    });
  }
  return pairs;
}

/** Every column of every public table, as text, that contains one of `needles`. */
async function columnsHolding(needles: string[]): Promise<string[]> {
  const columns = (await t.admin.execute(sql`
    select table_name, column_name from information_schema.columns
    where table_schema = 'public'
  `)) as unknown as { table_name: string; column_name: string }[];
  const found: string[] = [];
  for (const { table_name, column_name } of columns) {
    for (const needle of needles) {
      const rows = (await t.admin.execute(sql`
        select 1 from ${sql.identifier(table_name)}
        where ${sql.identifier(column_name)}::text like ${`%${needle}%`} limit 1
      `)) as unknown as unknown[];
      if (rows.length > 0) found.push(`${table_name}.${column_name}`);
    }
  }
  return found;
}

describe("an encrypted account's connect carries S", () => {
  test("S round-trips through consent, exchange and three refreshes", async () => {
    const S = newSecret();
    const pairs = await connectAndRefresh("roundtrip@wambito.test", S);
    for (const { accessToken, refreshToken } of pairs) {
      expect(refreshToken.endsWith(`.${S}`)).toBe(true);
      expect(refreshToken.split(".")).toHaveLength(2);
      expect(await openWk(accessToken)).toBe(S);
      const wrap = await t.request("GET", "/v2/keys/assistant", { headers: bearer(accessToken) });
      expect(wrap.status).toBe(404);
    }
    // Each refresh rotated the token Better Auth keeps.
    expect(new Set(pairs.map((p) => p.refreshToken)).size).toBe(4);
  });

  test("no column of any table holds S after the run", async () => {
    const S = newSecret();
    const pairs = await connectAndRefresh("no-column@wambito.test", S);
    const bytes = Buffer.from(S, "base64url");
    expect(await columnsHolding([S, bytes.toString("hex"), bytes.toString("base64")])).toEqual([]);
    // Positive control: the scan reads the rows the run wrote.
    const control = await columnsHolding([pairs[0]?.clientId ?? "missing"]);
    expect(control).toEqual(
      expect.arrayContaining(["oauth_client.client_id", "oauth_refresh_token.client_id"]),
    );
  });

  test("reusing a refresh token kills the family", async () => {
    const S = newSecret();
    const [first, second] = await connectAndRefresh("reuse@wambito.test", S);
    if (!first || !second) throw new Error("no tokens");
    expect((await refresh(first.refreshToken, first.clientId)).status).toBe(400);
    expect((await refresh(second.refreshToken, first.clientId)).status).toBe(400);
  });

  test("revoke with the suffixed token revokes", async () => {
    const S = newSecret();
    const { headers } = await encryptedUser("revoke-suffix@wambito.test");
    const tokens = await t.connectAssistant("revoke-suffix@wambito.test", { headers, wk: S });
    const res = await t.app.request("/auth/oauth2/revoke", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        token: tokens.refreshToken,
        token_type_hint: "refresh_token",
        client_id: tokens.clientId,
      }).toString(),
    });
    expect(res.status).toBe(200);
    expect((await refresh(tokens.refreshToken, tokens.clientId)).status).toBe(400);
  });

  test("introspect with the suffixed token answers active", async () => {
    const S = newSecret();
    const email = "introspect@wambito.test";
    const { headers } = await encryptedUser(email);
    // Introspection needs a confidential client.
    const registered = await t.request("POST", "/auth/oauth2/register", {
      body: {
        client_name: "Confidential",
        redirect_uris: [ASSISTANT_REDIRECT],
        token_endpoint_auth_method: "client_secret_post",
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
      },
    });
    expect(registered.status).toBe(201);
    const client = (await registered.json()) as { client_id: string; client_secret: string };
    const tokens = await t.connectAssistant(email, {
      headers,
      wk: S,
      clientId: client.client_id,
      clientSecret: client.client_secret,
    });
    expect(tokens.refreshToken.endsWith(`.${S}`)).toBe(true);
    const res = await t.app.request("/auth/oauth2/introspect", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        token: tokens.refreshToken,
        token_type_hint: "refresh_token",
        client_id: client.client_id,
        client_secret: client.client_secret,
      }).toString(),
    });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { active: boolean }).active).toBe(true);
  });

  test("an encrypted account's authorize always shows the consent page", async () => {
    const email = "always-consent@wambito.test";
    const { headers } = await encryptedUser(email);
    const { clientId } = await t.connectAssistant(email, { headers, wk: newSecret() });
    const { res } = await t.authorizeRequest(clientId, headers);
    expect(res.headers.get("location") ?? "").toMatch(
      new RegExp(`^${t.config.WEB_URL}/oauth/consent\\?`),
    );
  });

  test("an encrypted account without S gets 400 invalid_grant and the client is revoked", async () => {
    const email = "lost-secret@wambito.test";
    const { headers, userId } = await encryptedUser(email);
    const pending = await t.consentCode(email, { headers, wk: newSecret() });
    // The API restarted between consent and exchange: the map is empty.
    forgetPendingSecrets();
    const res = await t.exchangeCode(pending);
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toBe("invalid_grant");
    const consents = await t.admin
      .select()
      .from(oauthConsent)
      .where(and(eq(oauthConsent.userId, userId), eq(oauthConsent.clientId, pending.clientId)));
    expect(consents).toEqual([]);
    // The next connect goes through the consent page again, and works.
    const again = await t.connectAssistant(email, {
      headers,
      wk: newSecret(),
      clientId: pending.clientId,
    });
    expect(again.refreshToken).toContain(".");
  });

  test("an encrypted account connected without wk gets 400 invalid_grant", async () => {
    const email = "no-wk@wambito.test";
    const { headers } = await encryptedUser(email);
    const pending = await t.consentCode(email, { headers });
    const res = await t.exchangeCode(pending);
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toBe("invalid_grant");
  });

  test("a refresh without S for an encrypted account gets 400 invalid_grant and revokes", async () => {
    const email = "refresh-no-s@wambito.test";
    const { headers, userId } = await encryptedUser(email);
    const tokens = await t.connectAssistant(email, { headers, wk: newSecret() });
    const plain = tokens.refreshToken.slice(0, tokens.refreshToken.lastIndexOf("."));
    const res = await refresh(plain, tokens.clientId);
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toBe("invalid_grant");
    const consents = await t.admin
      .select()
      .from(oauthConsent)
      .where(and(eq(oauthConsent.userId, userId), eq(oauthConsent.clientId, tokens.clientId)));
    expect(consents).toEqual([]);
  });

  test("a consent with wk and no MCP key is 503 assistant_keys_missing", async () => {
    t.config.MCP_WK_PUBLIC_KEY = undefined;
    const email = "no-key@wambito.test";
    const { headers } = await encryptedUser(email);
    await expect(t.consentCode(email, { headers, wk: newSecret() })).rejects.toThrow(
      /consent failed: 503 .*assistant_keys_missing/,
    );
  });

  test("a wk that is not 32 bytes of base64url is refused", async () => {
    const email = "bad-wk@wambito.test";
    const { headers } = await encryptedUser(email);
    await expect(
      t.consentCode(email, { headers, wk: randomBytes(16).toString("base64url") }),
    ).rejects.toThrow(/consent failed: 400 .*invalid_request/);
  });

  test("the log output of a full run never contains S", async () => {
    const S = newSecret();
    const lines: string[] = [];
    const capture = (...args: unknown[]) => {
      lines.push(
        args.map((a) => (a instanceof Error ? `${a.message} ${a.stack}` : String(a))).join(" "),
      );
      lines.push(
        JSON.stringify(args, (_k, v) => (v instanceof Error ? { ...v, m: v.message } : v)),
      );
    };
    for (const method of ["log", "info", "warn", "error", "debug"] as const) {
      vi.spyOn(console, method).mockImplementation(capture);
    }
    const write = (chunk: unknown) => {
      lines.push(String(chunk));
      return true;
    };
    vi.spyOn(process.stdout, "write").mockImplementation(write);
    vi.spyOn(process.stderr, "write").mockImplementation(write);

    const [first, , , last] = await connectAndRefresh("logs@wambito.test", S);
    if (!first || !last) throw new Error("no tokens");
    // A reuse, the refusal path and a revoke, so the error paths run too.
    await refresh(first.refreshToken, first.clientId);
    await refresh(last.refreshToken.slice(0, -44), first.clientId);
    await t.app.request("/auth/oauth2/revoke", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token: last.refreshToken, client_id: first.clientId }).toString(),
    });
    console.log("capture works");
    vi.restoreAllMocks();

    expect(lines.join("\n")).toContain("capture works");
    const bytes = Buffer.from(S, "base64url");
    for (const needle of [S, bytes.toString("hex"), bytes.toString("base64")]) {
      expect(lines.join("\n")).not.toContain(needle);
    }
  });
});

// Better Auth's body parser lowercases the content type and accepts any header that contains the
// media type, so the wrapper must see every request Better Auth would parse.
describe("content types Better Auth accepts", () => {
  const MIXED_FORM = "Application/X-WWW-Form-Urlencoded; charset=UTF-8";
  const post = (path: string, form: Record<string, string>, contentType = MIXED_FORM) =>
    t.app.request(path, {
      method: "POST",
      headers: { "content-type": contentType },
      body: new URLSearchParams(form).toString(),
    });
  const exchange = (pending: Awaited<ReturnType<TestApp["consentCode"]>>) =>
    post("/auth/oauth2/token", {
      grant_type: "authorization_code",
      code: pending.code,
      redirect_uri: ASSISTANT_REDIRECT,
      client_id: pending.clientId,
      code_verifier: pending.verifier,
      resource: pending.resource ?? "",
    });

  test("a code exchange with a mixed-case content type carries S", async () => {
    const S = newSecret();
    const email = "mixed-exchange@wambito.test";
    const { headers } = await encryptedUser(email);
    const res = await exchange(await t.consentCode(email, { headers, wk: S }));
    expect(res.status).toBe(200);
    const body = (await res.json()) as { access_token: string; refresh_token: string };
    expect(body.refresh_token.endsWith(`.${S}`)).toBe(true);
    expect(await openWk(body.access_token)).toBe(S);
  });

  test("a code exchange with a mixed-case content type and no S is refused", async () => {
    const email = "mixed-refused@wambito.test";
    const { headers } = await encryptedUser(email);
    const res = await exchange(await t.consentCode(email, { headers }));
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toBe("invalid_grant");
  });

  test("a revoke with a mixed-case content type and the suffixed token revokes", async () => {
    const email = "mixed-revoke@wambito.test";
    const { headers } = await encryptedUser(email);
    const tokens = await t.connectAssistant(email, { headers, wk: newSecret() });
    const res = await post("/auth/oauth2/revoke", {
      token: tokens.refreshToken,
      token_type_hint: "refresh_token",
      client_id: tokens.clientId,
    });
    expect(res.status).toBe(200);
    expect((await refresh(tokens.refreshToken, tokens.clientId)).status).toBe(400);
  });

  test("a consent with a mixed-case JSON content type carries wk", async () => {
    const S = newSecret();
    const email = "mixed-consent@wambito.test";
    const { headers } = await encryptedUser(email);
    const clientId = await t.registerAssistant();
    const { res: auth, verifier } = await t.authorizeRequest(clientId, headers);
    const consent = await t.app.request("/auth/oauth2/consent", {
      method: "POST",
      headers: { ...headers, "content-type": "Application/JSON; charset=UTF-8" },
      body: JSON.stringify({
        accept: true,
        oauth_query: new URL(auth.headers.get("location") ?? "").search.slice(1),
        wk: S,
      }),
    });
    expect(consent.status).toBe(200);
    const code = new URL(((await consent.json()) as { url: string }).url).searchParams.get("code");
    const res = await exchange({
      code: code ?? "",
      verifier,
      clientId,
      resource: t.config.MCP_URL,
    });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { refresh_token: string }).refresh_token.endsWith(`.${S}`)).toBe(
      true,
    );
  });
});

describe("a plain account", () => {
  test("a plain account's second authorize skips the consent page, as today", async () => {
    const email = "plain-skip@wambito.test";
    const { headers } = await t.signIn(email);
    const { clientId } = await t.authorize(email, { headers });
    const { res } = await t.authorizeRequest(clientId, headers);
    expect(res.headers.get("location") ?? "").toMatch(new RegExp(`^${ASSISTANT_REDIRECT}\\?`));
  });

  test("a plain account without wk gets today's tokens", async () => {
    const tokens = await t.authorize("plain-today@wambito.test");
    expect(tokens.refreshToken).not.toContain(".");
    expect(payloadOf(tokens.accessToken)).not.toHaveProperty("wk");
    const res = await refresh(tokens.refreshToken, tokens.clientId);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { access_token: string; refresh_token: string };
    expect(body.refresh_token).not.toContain(".");
    expect(payloadOf(body.access_token)).not.toHaveProperty("wk");
  });
});
