import { randomUUID } from "node:crypto";
import { keyWraps, passkey } from "@wambito/db";
import { eq, sql } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test, vi } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";
import { createSoftPasskey } from "./soft-passkey.ts";

type Headers = { authorization: string };
interface KeyWrap {
  id: string;
  kind: string;
  ref: string | null;
  keyV: number;
  wrapped: string;
  publicKey: string | null;
  attestation: string | null;
  label: string | null;
  createdAt: string;
  lastUsedAt: string | null;
}
interface WrapInput {
  kind: string;
  ref?: string | null;
  keyV: number;
  wrapped: string;
  publicKey?: string | null;
  attestation?: string | null;
  label?: string | null;
}

let t: TestApp;
let people = 0;
beforeAll(async () => {
  t = await createTestApp();
});
afterAll(() => t?.stop());

const bytes = (length: number, fill = 7) => Buffer.alloc(length, fill).toString("base64url");
const bearer = (token: string): Headers => ({ authorization: `Bearer ${token}` });

async function person(): Promise<{ email: string; headers: Headers; userId: string }> {
  const email = `keys-${++people}@wambito.test`;
  return { email, ...(await t.signIn(email)) };
}

const recovery = (keyV = 1, overrides: Partial<WrapInput> = {}): WrapInput => ({
  kind: "recovery",
  ref: null,
  keyV,
  wrapped: bytes(48),
  ...overrides,
});
const device = (keyV = 1, overrides: Partial<WrapInput> = {}): WrapInput => ({
  kind: "device",
  ref: randomUUID(),
  keyV,
  wrapped: bytes(80),
  publicKey: bytes(32, 9),
  attestation: bytes(32, 5),
  label: "Pixel 9",
  ...overrides,
});

const putRaw = (headers: Headers, id: string, body: unknown) =>
  t.request("PUT", `/v2/keys/${id}`, { headers, body });

async function put(headers: Headers, body: WrapInput, id = randomUUID()): Promise<KeyWrap> {
  const res = await putRaw(headers, id, body);
  expect(res.status, await res.clone().text()).toBe(200);
  return (await res.json()) as KeyWrap;
}

async function list(headers: Headers): Promise<KeyWrap[]> {
  const res = await t.request("GET", "/v2/keys", { headers });
  expect(res.status).toBe(200);
  return ((await res.json()) as { wraps: KeyWrap[] }).wraps;
}

const rotateRaw = (headers: Headers, body: unknown) =>
  t.request("POST", "/v2/keys/rotate", { headers, body });

/** A link the server cannot open: any 60 bytes. */
const link = (fill = 3) => bytes(60, fill);

async function expectProblem(res: Response, status: number, code: string) {
  expect(res.status).toBe(status);
  expect(((await res.json()) as { code: string }).code).toBe(code);
}

describe("/v2/keys", () => {
  test("a new account has no wraps; the first wrap takes any keyV, and comes back as stored", async () => {
    const { headers } = await person();
    expect(await list(headers)).toEqual([]);

    const first = await put(headers, recovery(3));
    expect(first).toMatchObject({ kind: "recovery", ref: null, keyV: 3, wrapped: bytes(48) });
    const id = randomUUID();
    const stored = await put(headers, device(3), id);
    expect(stored).toMatchObject({
      id,
      kind: "device",
      keyV: 3,
      wrapped: bytes(80),
      publicKey: bytes(32, 9),
      attestation: bytes(32, 5),
      label: "Pixel 9",
      lastUsedAt: null,
    });
    expect(Date.parse(stored.createdAt)).not.toBeNaN();
    expect(await list(headers)).toEqual([first, stored]);
  });

  test("an account's first wrap must be its recovery wrap", async () => {
    const { email, headers, userId } = await person();
    const { clientId } = await t.authorize(email, { headers });
    const key = await createSoftPasskey(t.admin, userId, "localhost");
    for (const wrap of [
      device(1),
      { kind: "passkey", ref: key.credentialId, keyV: 1, wrapped: bytes(60) },
      { kind: "assistant", ref: clientId, keyV: 1, wrapped: bytes(60) },
    ]) {
      await expectProblem(await putRaw(headers, randomUUID(), wrap), 422, "recovery_required");
    }
    expect(await list(headers)).toEqual([]);
    await put(headers, recovery(1));
    await put(headers, device(1));
  });

  test("a wrap must use the account's current keyV", async () => {
    const { headers } = await person();
    await put(headers, recovery(2));
    await expectProblem(
      await putRaw(headers, randomUUID(), device(1)),
      409,
      "key_version_mismatch",
    );
    await expectProblem(
      await putRaw(headers, randomUUID(), device(3)),
      409,
      "key_version_mismatch",
    );
    await put(headers, device(2));
  });

  test("PUT on an existing id replaces that wrap", async () => {
    const { headers } = await person();
    const kept = await put(headers, recovery(1));
    const id = randomUUID();
    const first = await put(headers, device(1), id);
    const second = await put(headers, device(1, { ref: first.ref, label: "Firefox on Mac" }), id);
    expect(second.label).toBe("Firefox on Mac");
    expect(await list(headers)).toEqual([kept, second]);
  });

  test("a new recovery wrap replaces the existing one", async () => {
    const { headers } = await person();
    await put(headers, recovery(1));
    const next = await put(headers, recovery(1, { wrapped: bytes(48, 1) }));
    const wraps = await list(headers);
    expect(wraps).toEqual([next]);
    // Its id cannot be turned into another kind: the account would lose its recovery wrap.
    await expectProblem(await putRaw(headers, next.id, device(1)), 409, "recovery_required");
    expect(await list(headers)).toEqual([next]);
  });

  test("a passkey wrap needs one of the person's passkey credential ids", async () => {
    const { headers, userId } = await person();
    const other = await person();
    const theirs = await createSoftPasskey(t.admin, other.userId, "localhost");
    const mine = await createSoftPasskey(t.admin, userId, "localhost");
    const wrap = (ref: string): WrapInput => ({
      kind: "passkey",
      ref,
      keyV: 1,
      wrapped: bytes(60),
    });
    await put(headers, recovery(1));

    await expectProblem(await putRaw(headers, randomUUID(), wrap("nope")), 422, "unknown_passkey");
    await expectProblem(
      await putRaw(headers, randomUUID(), wrap(theirs.credentialId)),
      422,
      "unknown_passkey",
    );
    const stored = await put(headers, wrap(mine.credentialId));
    expect(stored.ref).toBe(mine.credentialId);
  });

  test("an assistant wrap needs an OAuth client the person consented to", async () => {
    const { email, headers } = await person();
    await put(headers, recovery(1));
    const stranger = await t.registerAssistant("Stranger");
    const wrap = (ref: string): WrapInput => ({
      kind: "assistant",
      ref,
      keyV: 1,
      wrapped: bytes(60),
    });
    await expectProblem(
      await putRaw(headers, randomUUID(), wrap(stranger)),
      422,
      "unknown_assistant",
    );
    const { clientId } = await t.authorize(email, { headers });
    expect((await put(headers, wrap(clientId))).ref).toBe(clientId);
  });

  test("a device wrap needs a public key and an attestation", async () => {
    const { headers } = await person();
    await put(headers, recovery(1));
    const missing = async (body: unknown) =>
      expectProblem(await putRaw(headers, randomUUID(), body), 422, "attestation_required");

    await missing({ ...device(), publicKey: undefined });
    await missing({ ...device(), publicKey: null });
    await missing({ ...device(), attestation: undefined });
    await missing({ ...device(), attestation: null });
    await expectProblem(
      await rotateRaw(headers, {
        keyV: 2,
        wraps: [
          { id: randomUUID(), ...recovery(2) },
          { id: randomUUID(), ...device(2, { attestation: null }) },
        ],
        link: link(),
      }),
      422,
      "attestation_required",
    );
    expect(await list(headers)).toHaveLength(1);
  });

  test("validates kinds, refs and byte lengths", async () => {
    const { headers } = await person();
    await put(headers, recovery(1));
    const invalid = async (body: unknown) =>
      expectProblem(await putRaw(headers, randomUUID(), body), 422, "validation_failed");

    await invalid({ ...device(), kind: "other" });
    await invalid({ ...device(), publicKey: bytes(31) });
    await invalid({ ...device(), publicKey: bytes(33) });
    await invalid({ ...device(), attestation: bytes(31) });
    await invalid({ ...device(), attestation: bytes(33) });
    await invalid({ ...device(), ref: null });
    await invalid({ ...device(), wrapped: "" });
    await invalid({ ...device(), wrapped: bytes(1025) });
    await invalid({ ...device(), wrapped: "not base64url!" });
    await invalid({ ...device(), label: "x".repeat(101) });
    await invalid({ ...recovery(), ref: "something" });
    await invalid({ ...recovery(), publicKey: bytes(32) });
    await invalid({ ...recovery(), attestation: bytes(32) });
    await expectProblem(await putRaw(headers, "not-a-uuid", device()), 422, "validation_failed");
    // Ids are lower-case UUIDs, as they enter the associated data; never lower-cased for you.
    const upper = randomUUID().toUpperCase();
    await expectProblem(await putRaw(headers, upper, device()), 422, "validation_failed");
    await expectProblem(
      await t.request("DELETE", `/v2/keys/${upper}`, { headers }),
      422,
      "validation_failed",
    );

    await put(headers, device(1, { wrapped: bytes(1024), label: "x".repeat(100) }));
    await put(headers, device(1, { wrapped: bytes(1) }));
  });

  test("DELETE removes a wrap, never the recovery wrap", async () => {
    const { headers } = await person();
    const kept = await put(headers, recovery(1));
    const gone = await put(headers, device(1));

    const res = await t.request("DELETE", `/v2/keys/${gone.id}`, { headers });
    expect(res.status).toBe(204);
    expect(await list(headers)).toEqual([kept]);
    await expectProblem(
      await t.request("DELETE", `/v2/keys/${gone.id}`, { headers }),
      404,
      "not_found",
    );
    await expectProblem(
      await t.request("DELETE", `/v2/keys/${kept.id}`, { headers }),
      409,
      "recovery_required",
    );
    expect(await list(headers)).toEqual([kept]);
  });

  describe("rotate", () => {
    test("replaces every wrap with keyV + 1, in one go", async () => {
      const { headers } = await person();
      await put(headers, recovery(4));
      await put(headers, device(4));
      const next = [
        { id: randomUUID(), ...recovery(5) },
        { id: randomUUID(), ...device(5, { label: "Kept phone" }) },
      ];
      const res = await rotateRaw(headers, { keyV: 5, wraps: next, link: link() });
      expect(res.status, await res.clone().text()).toBe(200);
      const { wraps } = (await res.json()) as { wraps: KeyWrap[] };
      const byId = (a: KeyWrap, b: KeyWrap) => a.id.localeCompare(b.id);
      expect(wraps.map((w) => w.id).sort()).toEqual(next.map((w) => w.id).sort());
      expect(wraps.every((w) => w.keyV === 5)).toBe(true);
      expect((await list(headers)).sort(byId)).toEqual([...wraps].sort(byId));
      // The new keyV is the current one.
      await expectProblem(
        await putRaw(headers, randomUUID(), device(4)),
        409,
        "key_version_mismatch",
      );
      await put(headers, device(5));
    });

    test("refuses a keyV other than current + 1, and leaves the wraps alone", async () => {
      const { headers } = await person();
      const kept = await put(headers, recovery(1));
      for (const keyV of [1, 3]) {
        await expectProblem(
          await rotateRaw(headers, {
            keyV,
            wraps: [{ id: randomUUID(), ...recovery(keyV) }],
            link: link(),
          }),
          409,
          "key_version_mismatch",
        );
      }
      expect(await list(headers)).toEqual([kept]);
    });

    test("needs exactly one recovery wrap", async () => {
      const { headers } = await person();
      const kept = await put(headers, recovery(1));
      await expectProblem(
        await rotateRaw(headers, {
          keyV: 2,
          wraps: [{ id: randomUUID(), ...device(2) }],
          link: link(),
        }),
        422,
        "recovery_required",
      );
      await expectProblem(
        await rotateRaw(headers, {
          keyV: 2,
          wraps: [
            { id: randomUUID(), ...recovery(2) },
            { id: randomUUID(), ...recovery(2) },
          ],
          link: link(),
        }),
        422,
        "recovery_required",
      );
      expect(await list(headers)).toEqual([kept]);
    });

    test("a wrap id that is not a lower-case UUID", async () => {
      const { headers } = await person();
      const kept = await put(headers, recovery(1));
      await expectProblem(
        await rotateRaw(headers, {
          keyV: 2,
          wraps: [{ id: randomUUID().toUpperCase(), ...recovery(2) }],
          link: link(),
        }),
        422,
        "validation_failed",
      );
      expect(await list(headers)).toEqual([kept]);
    });

    test("one person's rotation leaves another's wraps untouched", async () => {
      const a = await person();
      const b = await person();
      const aWraps = [await put(a.headers, recovery(1)), await put(a.headers, device(1))];
      const bWraps = [await put(b.headers, recovery(1)), await put(b.headers, device(1))];
      const byId = (x: KeyWrap, y: KeyWrap) => x.id.localeCompare(y.id);

      const rotated = await rotateRaw(a.headers, {
        keyV: 2,
        wraps: [{ id: randomUUID(), ...recovery(2) }],
        link: link(),
      });
      expect(rotated.status).toBe(200);
      expect((await list(b.headers)).sort(byId)).toEqual([...bWraps].sort(byId));

      const back = await rotateRaw(b.headers, {
        keyV: 2,
        wraps: [{ id: randomUUID(), ...recovery(2) }],
        link: link(),
      });
      expect(back.status).toBe(200);
      const aNow = await list(a.headers);
      expect(aNow).toHaveLength(1);
      expect(aNow[0]?.keyV).toBe(2);
      expect(aWraps.map((w) => w.id)).not.toContain(aNow[0]?.id);
      // Each rotation replaced only its own person's wraps.
      const all = await t.admin.select({ id: keyWraps.id, userId: keyWraps.userId }).from(keyWraps);
      expect(all.filter((w) => w.userId === a.userId)).toHaveLength(1);
      expect(all.filter((w) => w.userId === b.userId)).toHaveLength(1);
    });

    test("every wrap carries the new keyV and passes the same checks as PUT", async () => {
      const { headers } = await person();
      const kept = await put(headers, recovery(1));
      await expectProblem(
        await rotateRaw(headers, {
          keyV: 2,
          wraps: [
            { id: randomUUID(), ...recovery(2) },
            { id: randomUUID(), ...device(1) },
          ],
          link: link(),
        }),
        422,
        "validation_failed",
      );
      await expectProblem(
        await rotateRaw(headers, {
          keyV: 2,
          wraps: [
            { id: randomUUID(), ...recovery(2) },
            { id: randomUUID(), kind: "passkey", ref: "nope", keyV: 2, wrapped: bytes(60) },
          ],
          link: link(),
        }),
        422,
        "unknown_passkey",
      );
      expect(await list(headers)).toEqual([kept]);
    });
  });

  test("deleting a passkey through Better Auth removes its wrap, and only after it succeeds", async () => {
    const { headers, userId } = await person();
    const other = await person();
    const gone = await createSoftPasskey(t.admin, userId, "localhost");
    const kept = await createSoftPasskey(t.admin, userId, "localhost");
    const wrap = (ref: string): WrapInput => ({
      kind: "passkey",
      ref,
      keyV: 1,
      wrapped: bytes(60),
    });
    const recoveryWrap = await put(headers, recovery(1));
    await put(headers, wrap(gone.credentialId));
    const keptWrap = await put(headers, wrap(kept.credentialId));
    const [row] = await t.admin
      .select({ id: passkey.id })
      .from(passkey)
      .where(eq(passkey.credentialID, gone.credentialId));
    const passkeyId = row?.id as string;

    // Someone else cannot delete it, and the wrap stays.
    const refused = await t.request("POST", "/auth/passkey/delete-passkey", {
      headers: other.headers,
      body: { id: passkeyId },
    });
    expect(refused.status).not.toBe(200);
    expect(await list(headers)).toHaveLength(3);

    const res = await t.request("POST", "/auth/passkey/delete-passkey", {
      headers,
      body: { id: passkeyId },
    });
    expect(res.status, await res.clone().text()).toBe(200);
    expect(await list(headers)).toEqual([recoveryWrap, keptWrap]);
  });

  describe("key links", () => {
    const oneRecovery = (keyV: number) => [{ id: randomUUID(), ...recovery(keyV) }];
    const getLinks = async (headers: Headers) => {
      const res = await t.request("GET", "/v2/keys", { headers });
      expect(res.status).toBe(200);
      return ((await res.json()) as { links: { keyV: number; link: string }[] }).links;
    };

    test("a rotation of an account with a version needs a link (422 link_required) and changes nothing", async () => {
      const { headers } = await person();
      const kept = await put(headers, recovery(1));
      await expectProblem(
        await rotateRaw(headers, { keyV: 2, wraps: oneRecovery(2) }),
        422,
        "link_required",
      );
      await expectProblem(
        await rotateRaw(headers, { keyV: 2, wraps: oneRecovery(2), link: null }),
        422,
        "link_required",
      );
      expect(await list(headers)).toEqual([kept]);
      expect(await getLinks(headers)).toEqual([]);
    });

    test("a link on the first version is 422 link_unexpected", async () => {
      const { headers } = await person();
      await expectProblem(
        await rotateRaw(headers, { keyV: 1, wraps: oneRecovery(1), link: link() }),
        422,
        "link_unexpected",
      );
      expect(await list(headers)).toEqual([]);
      const res = await rotateRaw(headers, { keyV: 1, wraps: oneRecovery(1) });
      expect(res.status).toBe(200);
      expect(((await res.json()) as { links: unknown[] }).links).toEqual([]);
    });

    test("a link that is not 60 bytes is 422 invalid_link", async () => {
      const { headers } = await person();
      const kept = await put(headers, recovery(1));
      for (const length of [1, 59, 61, 200]) {
        await expectProblem(
          await rotateRaw(headers, {
            keyV: 2,
            wraps: oneRecovery(2),
            link: bytes(length),
          }),
          422,
          "invalid_link",
        );
      }
      expect(await list(headers)).toEqual([kept]);
    });

    test("GET /v2/keys lists the links in keyV order, and they survive later rotations", async () => {
      const { headers } = await person();
      await put(headers, recovery(1));
      const first = await rotateRaw(headers, {
        keyV: 2,
        wraps: oneRecovery(2),
        link: link(4),
      });
      expect(first.status, await first.clone().text()).toBe(200);
      expect(((await first.json()) as { links: unknown[] }).links).toEqual([
        { keyV: 2, link: link(4) },
      ]);
      const second = await rotateRaw(headers, {
        keyV: 3,
        wraps: oneRecovery(3),
        link: link(5),
      });
      expect(second.status).toBe(200);
      const expected = [
        { keyV: 2, link: link(4) },
        { keyV: 3, link: link(5) },
      ];
      expect(((await second.json()) as { links: unknown[] }).links).toEqual(expected);
      expect(await getLinks(headers)).toEqual(expected);
    });

    test("one person never sees another's links", async () => {
      const a = await person();
      const b = await person();
      await put(a.headers, recovery(1));
      await put(b.headers, recovery(1));
      await rotateRaw(a.headers, { keyV: 2, wraps: oneRecovery(2), link: link(8) });
      expect(await getLinks(a.headers)).toHaveLength(1);
      expect(await getLinks(b.headers)).toEqual([]);
    });
  });

  describe("assistants", () => {
    test("a token reaches only GET /v2/keys/assistant, which returns its own client's wrap", async () => {
      const { email, headers } = await person();
      const first = await t.authorize(email, { headers });
      const second = await t.authorize(email, { headers, scope: "finance:write" });
      const assistantWrap = (ref: string, fill: number): WrapInput => ({
        kind: "assistant",
        ref,
        keyV: 1,
        wrapped: bytes(60, fill),
      });
      await put(headers, recovery(1));
      const firstWrap = await put(headers, assistantWrap(first.clientId, 1));
      const secondWrap = await put(headers, assistantWrap(second.clientId, 2));

      for (const token of [first, second]) {
        const h = bearer(token.accessToken);
        const res = await t.request("GET", "/v2/keys/assistant", { headers: h });
        expect(res.status).toBe(200);
        const wrap = (await res.json()) as KeyWrap;
        const expected = token === first ? firstWrap : secondWrap;
        expect(wrap).toMatchObject({
          id: expected.id,
          ref: token.clientId,
          wrapped: expected.wrapped,
        });
        expect(wrap.lastUsedAt).not.toBeNull();
      }
      const stored = await t.admin
        .select({ lastUsedAt: keyWraps.lastUsedAt })
        .from(keyWraps)
        .where(eq(keyWraps.id, firstWrap.id));
      expect(stored[0]?.lastUsedAt).toBeInstanceOf(Date);

      // Both scopes, every other route: 403.
      const h = bearer(first.accessToken);
      const id = randomUUID();
      for (const res of [
        await t.request("GET", "/v2/keys", { headers: h }),
        await putRaw(h, id, device(1)),
        await t.request("DELETE", `/v2/keys/${firstWrap.id}`, { headers: h }),
        await rotateRaw(h, { keyV: 2, wraps: [{ id, ...recovery(2) }], link: link() }),
        await t.request("PUT", "/v2/keys/assistant", { headers: h, body: device(1) }),
        await t.request("DELETE", "/v2/keys/assistant", { headers: h }),
      ]) {
        await expectProblem(res, 403, "insufficient_scope");
      }
      expect(await list(headers)).toHaveLength(3);
    });

    test("an assistant without a wrap gets 404; a session gets 404", async () => {
      const { email, headers } = await person();
      const token = await t.authorize(email, { headers });
      await expectProblem(
        await t.request("GET", "/v2/keys/assistant", { headers: bearer(token.accessToken) }),
        404,
        "not_found",
      );
      await put(headers, recovery(1));
      await expectProblem(
        await t.request("GET", "/v2/keys/assistant", { headers }),
        404,
        "not_found",
      );
    });
  });

  test("row-level security: one person never sees nor touches another's wraps", async () => {
    const a = await person();
    const b = await person();
    await put(a.headers, recovery(1));
    const theirs = await put(a.headers, device(1));
    await put(b.headers, recovery(7));

    expect((await list(b.headers)).map((w) => w.id)).not.toContain(theirs.id);
    await expectProblem(
      await t.request("DELETE", `/v2/keys/${theirs.id}`, { headers: b.headers }),
      404,
      "not_found",
    );
    await expectProblem(await putRaw(b.headers, theirs.id, device(7)), 409, "id_taken");
    // A's keyV is not B's.
    await put(a.headers, device(1));
    expect(await list(a.headers)).toHaveLength(3);
  });

  test("a database failure logs no wrapped bytes", async () => {
    const { headers } = await person();
    const marker = Buffer.from("MARKER-keys-4c1b-do-not-log!!!!!!!!!!!!!!!!!").toString(
      "base64url",
    );
    await t.admin.execute(sql`create or replace function fail_wrap_insert() returns trigger
      language plpgsql as $$ begin raise exception 'forced failure'; end $$`);
    await t.admin.execute(sql`create trigger fail_wrap before insert on key_wraps
      for each row execute function fail_wrap_insert()`);
    const spies = (["log", "info", "warn", "error", "debug"] as const).map((level) =>
      vi.spyOn(console, level).mockImplementation(() => {}),
    );
    try {
      const res = await putRaw(headers, randomUUID(), recovery(1, { wrapped: marker }));
      expect(res.status).toBe(500);
      const logged = JSON.stringify(spies.flatMap((spy) => spy.mock.calls));
      expect(logged).toContain("database query failed");
      expect(logged).not.toContain("MARKER-keys");
      expect(logged).not.toContain(marker);
    } finally {
      vi.restoreAllMocks();
      await t.admin.execute(sql`drop trigger fail_wrap on key_wraps`);
    }
  });
});

describe("PUT /v2/keys/{id} with If-None-Match: *", () => {
  const putFirst = (headers: Headers, id: string, body: WrapInput) =>
    t.request("PUT", `/v2/keys/${id}`, { headers: { ...headers, "if-none-match": "*" }, body });

  test("stores the first recovery wrap of an account without wraps", async () => {
    const { headers } = await person();
    const id = randomUUID();
    const res = await putFirst(headers, id, recovery());
    expect(res.status).toBe(200);
    expect((await list(headers)).map((w) => w.id)).toEqual([id]);
  });

  test("is 409 already_set_up once the account has a wrap, and changes nothing", async () => {
    const { headers } = await person();
    const first = await put(headers, recovery(1, { wrapped: bytes(48, 1) }));
    const res = await putFirst(headers, randomUUID(), recovery(1, { wrapped: bytes(48, 2) }));
    expect(res.status).toBe(409);
    expect(await res.json()).toMatchObject({ code: "already_set_up" });
    expect(await list(headers)).toEqual([first]);
  });

  test("a retry of the same id goes through (its first answer was lost)", async () => {
    const { headers } = await person();
    const id = randomUUID();
    expect((await putFirst(headers, id, recovery())).status).toBe(200);
    expect((await putFirst(headers, id, recovery())).status).toBe(200);
    expect(await list(headers)).toHaveLength(1);
  });

  test("two setups at once: exactly one wins", async () => {
    const { headers } = await person();
    const results = await Promise.all(
      [1, 2, 3].map((n) => putFirst(headers, randomUUID(), recovery(1, { wrapped: bytes(48, n) }))),
    );
    expect(results.map((r) => r.status).sort()).toEqual([200, 409, 409]);
    expect(await list(headers)).toHaveLength(1);
  });

  test("any other If-None-Match is 422", async () => {
    const { headers } = await person();
    const res = await t.request("PUT", `/v2/keys/${randomUUID()}`, {
      headers: { ...headers, "if-none-match": '"abc"' },
      body: recovery(),
    });
    expect(res.status).toBe(422);
  });
});

describe("a removed device loses its session", () => {
  /** Two sessions of one person, and the id of the wrap B's session registers for its device. */
  async function twoSessions() {
    const { email, headers: a, userId } = await person();
    const { headers: b } = await t.signIn(email);
    await put(a, recovery(1));
    return { a, b, userId };
  }
  const sessionOf = async (userId: string) =>
    (await t.admin.execute(sql`select id from session where user_id = ${userId}`)) as unknown as {
      id: string;
    }[];
  const storedSession = async (id: string) => {
    const rows = await t.admin
      .select({ sessionId: keyWraps.sessionId })
      .from(keyWraps)
      .where(eq(keyWraps.id, id));
    return rows[0]?.sessionId;
  };
  const status = async (headers: Headers) =>
    (await t.request("GET", "/v2/keys", { headers })).status;

  test("a device PUT stores the caller's session; other kinds store none", async () => {
    const { a, userId } = await twoSessions();
    const wrap = await put(a, device(1));
    const stored = await storedSession(wrap.id);
    expect(stored).toBeTruthy();
    expect((await sessionOf(userId)).map((s) => s.id)).toContain(stored);
    const [rec] = await list(a);
    expect(await storedSession((rec as KeyWrap).id)).toBeNull();
  });

  test("DELETE of a device wrap ends that device's session: its next GET /v2/keys is 401", async () => {
    const { a, b } = await twoSessions();
    const wrap = await put(b, device(1));
    expect(await status(b)).toBe(200);
    expect((await t.request("DELETE", `/v2/keys/${wrap.id}`, { headers: a })).status).toBe(204);
    expect(await status(b)).toBe(401);
    expect(await status(a)).toBe(200);
  });

  test("a rotation that leaves a device out ends its session; kept devices keep theirs", async () => {
    const { email, headers: a, userId } = await person();
    const { headers: b } = await t.signIn(email);
    const { headers: c } = await t.signIn(email);
    await put(a, recovery(1));
    const keptRef = randomUUID();
    const kept = await put(b, device(1, { ref: keptRef }));
    await put(c, device(1));
    const oldSession = await storedSession(kept.id);
    const res = await rotateRaw(a, {
      keyV: 2,
      wraps: [
        { id: randomUUID(), ...recovery(2) },
        { id: randomUUID(), ...device(2, { ref: keptRef }) },
      ],
      link: link(),
    });
    expect(res.status, await res.clone().text()).toBe(200);
    const { wraps } = (await res.json()) as { wraps: KeyWrap[] };
    const newKept = wraps.find((w) => w.kind === "device") as KeyWrap;
    expect(await storedSession(newKept.id)).toBe(oldSession);
    expect(await status(b)).toBe(200);
    expect(await status(c)).toBe(401);
    expect(await status(a)).toBe(200);
    expect(await sessionOf(userId)).toHaveLength(2);
  });

  test("the caller's own session is never ended", async () => {
    const { a } = await twoSessions();
    const wrap = await put(a, device(1));
    expect((await t.request("DELETE", `/v2/keys/${wrap.id}`, { headers: a })).status).toBe(204);
    expect(await status(a)).toBe(200);
  });

  test("a device wrap whose session is gone (null) is removed and rotated away without error", async () => {
    const { a, b, userId } = await twoSessions();
    const gone = await put(b, device(1));
    const other = await put(a, device(1));
    await t.admin.execute(sql`delete from session where id = ${await storedSession(gone.id)}`);
    expect(await storedSession(gone.id)).toBeNull();
    expect((await t.request("DELETE", `/v2/keys/${gone.id}`, { headers: a })).status).toBe(204);
    const wraps = await list(a);
    expect(wraps.map((w) => w.id)).toContain(other.id);
    const res = await rotateRaw(a, {
      keyV: 2,
      wraps: [{ id: randomUUID(), ...recovery(2) }],
      link: link(),
    });
    expect(res.status).toBe(200);
    expect(await status(a)).toBe(200);
    expect(userId).toBeTruthy();
  });
});
