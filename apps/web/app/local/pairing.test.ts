import "fake-indexeddb/auto";
import {
  deriveRecordKeys,
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  openRecord,
  pairingCode,
  pairingCommitment,
  sealRecord,
  sealToDevice,
  toBase64Url,
  verifyDeviceAttestation,
} from "@wambito/crypto";
import { describe, expect, it, vi } from "vitest";

/** What the crypto handed out or was asked for, to check zeroing and the seal's context. */
const handed = vi.hoisted(() => ({
  openedDevice: [] as Uint8Array[],
  openedPairing: [] as Uint8Array[],
  seals: [] as Array<{ ctx: unknown; ephemeral: boolean; dataKey: Uint8Array }>,
}));
vi.mock("@wambito/crypto", async (original) => {
  const crypto = await original<typeof import("@wambito/crypto")>();
  return {
    ...crypto,
    openFromDevice: async (...args: Parameters<typeof crypto.openFromDevice>) => {
      const out = await crypto.openFromDevice(...args);
      handed.openedDevice.push(out);
      return out;
    },
    openFromPairing: async (...args: Parameters<typeof crypto.openFromPairing>) => {
      const out = await crypto.openFromPairing(...args);
      handed.openedPairing.push(out);
      return out;
    },
    sealToDevice: async (...args: Parameters<typeof crypto.sealToDevice>) => {
      const [, ctx, dataKey, ephemeral] = args;
      handed.seals.push({ ctx, ephemeral: ephemeral !== undefined, dataKey });
      return crypto.sealToDevice(...args);
    },
  };
});

import { enrollDevice, type KeysOptions } from "./keys.ts";
import { findPairing, PairingError, type PairingOptions, startPairing } from "./pairing.ts";

const TTL = 10 * 60 * 1000;
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const problem = (status: number, code: string) => json({ code }, status);

interface Row {
  id: string;
  code: string;
  commitment: string;
  approverKey: string | null;
  publicKey: string | null;
  sealed: string | null;
  keyV: number | null;
  expiresAt: number;
}

interface Wrap {
  id: string;
  kind: string;
  keyV: number;
  wrapped: string;
  publicKey: string | null;
  attestation: string | null;
}

/** `normalizePairingCode` of `apps/api/src/services/pairing.ts`. */
const normalize = (input: string) =>
  input.toUpperCase().replace(/[-\s]/g, "").replace(/[IL]/g, "1").replace(/O/g, "0");

/**
 * One account's server: the `/v2/pairing` relay with the rules of `services/pairing.ts` (stage 1b
 * spec section 1) and enough of `/v2/keys` for the approving browser's device wrap and the new
 * device's enroll. Tamper hooks stand in for a malicious server.
 */
function fakeServer(clock: { t: number }) {
  const state = {
    rows: new Map<string, Row>(),
    wraps: [] as Wrap[],
    log: [] as string[],
    /** The relay never expires rows: only the clients' own clocks stop them. */
    ignoreExpiry: false,
    /** How long the relay says a new request lives (a hostile relay may say much longer). */
    ttl: TTL,
    onGet: undefined as undefined | ((body: Record<string, unknown>, row: Row) => void),
    onPickup: undefined as undefined | ((body: { sealed: string; keyV: number }) => void),
  };
  const current = () => Math.max(0, ...state.wraps.map((w) => w.keyV));
  const live = (id: string) => {
    const row = state.rows.get(id);
    if (!row || (!state.ignoreExpiry && row.expiresAt <= clock.t)) return undefined;
    return row;
  };
  const answer = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const url = new URL(String(input), "http://x");
    const method = init?.method ?? "GET";
    const headers = (init?.headers ?? {}) as Record<string, string>;
    expect(headers["x-wambito-user"]).toBeTruthy();
    state.log.push(`${method} ${url.pathname}${url.search}`);
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    const path = url.pathname.replace(/^\/api/, "");

    if (path === "/v2/keys" && method === "GET") return json({ wraps: state.wraps });
    const put = /^\/v2\/keys\/([0-9a-f-]{36})$/.exec(path);
    if (put && method === "PUT") {
      if (state.wraps.length > 0 && body.keyV !== current()) {
        return problem(409, "key_version_mismatch");
      }
      state.wraps.push({ id: put[1] as string, ...body });
      return json(body);
    }

    if (path === "/v2/pairing" && method === "POST") {
      const id = crypto.randomUUID();
      const row: Row = {
        id,
        code: pairingCode(),
        commitment: body.commitment,
        approverKey: null,
        publicKey: null,
        sealed: null,
        keyV: null,
        expiresAt: clock.t + state.ttl,
      };
      state.rows.set(id, row);
      return json({ id, code: row.code, expiresAt: new Date(row.expiresAt).toISOString() }, 201);
    }
    if (path === "/v2/pairing" && method === "GET") {
      const code = normalize(url.searchParams.get("code") ?? "");
      const row = [...state.rows.values()].find(
        (r) => r.code === code && r.approverKey === null && live(r.id),
      );
      if (!row) return problem(404, "not_found");
      return json({
        id: row.id,
        commitment: row.commitment,
        expiresAt: new Date(row.expiresAt).toISOString(),
      });
    }
    const match = /^\/v2\/pairing\/([0-9a-f-]{36})(?:\/(\w+))?$/.exec(path);
    if (!match) return new Response(null, { status: 404 });
    const row = live(match[1] as string);
    if (!row) return problem(404, "not_found");
    const action = match[2];
    if (!action && method === "GET") {
      const out: Record<string, unknown> = {
        commitment: row.commitment,
        approverKey: row.approverKey,
        publicKey: row.publicKey,
        sealed: row.sealed,
        keyV: row.keyV,
        expiresAt: new Date(row.expiresAt).toISOString(),
      };
      state.onGet?.(out, row);
      return json(out);
    }
    if (action === "approver" && method === "POST") {
      if (row.approverKey) return problem(409, "already_set");
      row.approverKey = body.publicKey;
      return new Response(null, { status: 204 });
    }
    if (action === "reveal" && method === "POST") {
      if (!row.approverKey) return problem(409, "not_ready");
      if (row.publicKey) return problem(409, "already_set");
      const hash = toBase64Url(await pairingCommitment(fromBase64Url(body.publicKey)));
      if (hash !== row.commitment) return problem(422, "commitment_mismatch");
      row.publicKey = body.publicKey;
      return new Response(null, { status: 204 });
    }
    if (action === "seal" && method === "POST") {
      if (row.sealed) return problem(409, "already_sealed");
      if (!row.approverKey || !row.publicKey) return problem(409, "not_ready");
      const blob = fromBase64Url(body.sealed);
      if (toBase64Url(blob.slice(0, 32)) !== row.approverKey) {
        return problem(422, "approver_mismatch");
      }
      if (body.keyV !== current()) return problem(409, "key_version_mismatch");
      row.sealed = body.sealed;
      row.keyV = body.keyV;
      return new Response(null, { status: 204 });
    }
    if (action === "pickup" && method === "POST") {
      if (!row.sealed || row.keyV === null) return problem(409, "not_ready");
      state.rows.delete(row.id);
      const out = { sealed: row.sealed, keyV: row.keyV };
      state.onPickup?.(out);
      return json(out);
    }
    return new Response(null, { status: 404 });
  };
  return Object.assign(state, { fetch: answer as typeof globalThis.fetch });
}

let counter = 0;

/**
 * An account whose approving browser holds a device wrap at key version 2 in this (fake)
 * IndexedDB, a shared fake clock whose `sleep` moves time on, and options for both devices.
 */
async function world() {
  const clock = { t: Date.parse("2026-11-10T12:00:00Z") };
  const sleeps: number[] = [];
  const server = fakeServer(clock);
  const userId = `pairing_user_${++counter}`;
  const dataKey = generateDataKey();
  const base: KeysOptions = { userId, fetch: server.fetch };
  await enrollDevice(base, dataKey, 2);
  // the setup's own requests (its enroll lists the keys for their links) are not the test's
  server.log.length = 0;
  handed.openedDevice.length = 0;
  handed.openedPairing.length = 0;
  handed.seals.length = 0;
  const options: PairingOptions = {
    ...base,
    clock: {
      now: () => clock.t,
      sleep: async (ms) => {
        sleeps.push(ms);
        clock.t += ms;
        await new Promise((resolve) => setTimeout(resolve, 0));
      },
    },
  };
  return { clock, sleeps, server, userId, dataKey, options };
}

const pairingErrorOf = async (promise: Promise<unknown>) => {
  try {
    await promise;
  } catch (error) {
    if (error instanceof PairingError) return error.code;
    throw error;
  }
  throw new Error("expected a PairingError");
};

const ticks = async (n: number) => {
  for (let i = 0; i < n; i++) await new Promise((resolve) => setTimeout(resolve, 0));
};

describe("pairing", () => {
  it("the happy path", async () => {
    const w = await world();
    const fresh = await startPairing(w.options);
    expect(fresh.code).toMatch(/^[0-9A-HJKMNP-TV-Z]{8}$/);
    expect(fresh.qr).toMatch(new RegExp(`^wambito://pair\\?id=${fresh.id}&key=[A-Za-z0-9_-]{43}$`));
    // the QR's key is the one behind the commitment
    const qrKey = fromBase64Url(fresh.qr.split("&key=")[1] as string);
    expect(toBase64Url(await pairingCommitment(qrKey))).toBe(
      w.server.rows.get(fresh.id)?.commitment,
    );

    const approver = await findPairing({ ...w.options, code: fresh.code });
    const [a, b] = await Promise.all([fresh.number(), approver.number()]);
    expect(a).toMatch(/^\d{6}$/);
    expect(a).toBe(b);

    const [keys] = await Promise.all([fresh.finish(), approver.approve()]);
    expect(keys.keyring.current).toBe(2);
    const ctx = { userId: w.userId, type: "settings" as const, id: crypto.randomUUID(), keyV: 2 };
    const sealed = await sealRecord(await deriveRecordKeys(w.dataKey, false), ctx, { s: 1 });
    expect(await openRecord(keys.keyring.byVersion.get(2) as never, ctx, sealed)).toEqual({ s: 1 });
    expect(w.server.rows.size).toBe(0);

    // the new device registered its own attested device wrap (addendum step 8)
    const enrolled = w.server.wraps.at(-1) as Wrap;
    expect(enrolled.kind).toBe("device");
    expect(enrolled.keyV).toBe(2);
    expect(enrolled.publicKey).not.toBe(fresh.qr.split("&key=")[1]);
    expect(
      await verifyDeviceAttestation(
        w.dataKey,
        {
          userId: w.userId,
          wrapId: enrolled.id,
          publicKey: fromBase64Url(enrolled.publicKey as string),
        },
        fromBase64Url(enrolled.attestation as string),
      ),
    ).toBe(true);
    // the DK the new device opened is zeroed once it enrolled
    expect(handed.openedPairing).toHaveLength(1);
    expect(handed.openedPairing[0]?.every((x) => x === 0)).toBe(true);
    // every poll waits 1.5 s
    expect(w.sleeps.length).toBeGreaterThan(0);
    expect(new Set(w.sleeps)).toEqual(new Set([1500]));
  });

  it("the approver pins the commitment from ?code=", async () => {
    const w = await world();
    const fresh = await startPairing(w.options);
    const approver = await findPairing({ ...w.options, code: fresh.code });
    // the server now shows another commitment and a revealed key that matches it
    const evil = await generateDeviceKeyPair();
    const evilKey = toBase64Url(evil.publicKey);
    const evilCommitment = toBase64Url(await pairingCommitment(evil.publicKey));
    w.server.onGet = (body) => {
      body.commitment = evilCommitment;
      if (body.publicKey) body.publicKey = evilKey;
    };
    const approverNumber = approver.number();
    fresh.number().catch(() => {});
    expect(await pairingErrorOf(approverNumber)).toBe("tampered");
    // number() never resolved: approve() refuses and sends nothing
    await expect(approver.approve()).rejects.toThrow("approve before number");
    expect(w.server.log.some((l) => l.endsWith("/seal"))).toBe(false);
    fresh.cancel();
  });

  it("the new device pins the first approverKey", async () => {
    const w = await world();
    const fresh = await startPairing(w.options);
    const approver = await findPairing({ ...w.options, code: fresh.code });
    const evil = toBase64Url((await generateDeviceKeyPair()).publicKey);
    let seen = 0;
    w.server.onGet = (body) => {
      if (body.approverKey && ++seen > 1) body.approverKey = evil;
    };
    await fresh.number();
    expect(await pairingErrorOf(fresh.finish())).toBe("tampered");
    const reveals = w.server.log.filter((l) => l.endsWith("/reveal"));
    // only the pinned key was answered with a reveal; none followed the other key
    expect(reveals).toHaveLength(1);
    expect(w.server.log.some((l) => l.endsWith("/pickup"))).toBe(false);
    approver.cancel();
  });

  it("a later approverKey seen before the reveal is tampered and no reveal is sent", async () => {
    const w = await world();
    const evil = toBase64Url((await generateDeviceKeyPair()).publicKey);
    // the reveal fails once (409 not_ready from the server); the retry follows the next poll
    let first = true;
    const fetch = w.server.fetch;
    const options: PairingOptions = {
      ...w.options,
      fetch: async (input, init) => {
        if (String(input).endsWith("/reveal") && first) {
          first = false;
          w.server.onGet = (body) => {
            if (body.approverKey) body.approverKey = evil;
          };
          return problem(409, "not_ready");
        }
        return fetch(input, init);
      },
    };
    const again = await startPairing(options);
    const other = await findPairing({ ...w.options, code: again.code });
    expect(await pairingErrorOf(again.number())).toBe("tampered");
    expect(w.server.log.filter((l) => l.endsWith(`${again.id}/reveal`))).toHaveLength(0);
    other.cancel();
  });

  it("a QR whose key is not the revealed key is tampered", async () => {
    const w = await world();
    const fresh = await startPairing(w.options);
    const other = toBase64Url((await generateDeviceKeyPair()).publicKey);
    const qr = `wambito://pair?id=${fresh.id}&key=${other}`;
    expect(await pairingErrorOf(findPairing({ ...w.options, qr }))).toBe("tampered");
    // nothing was posted for a request the QR does not match
    expect(w.server.rows.get(fresh.id)?.approverKey).toBeNull();

    // the real QR works, and the approver still checks the revealed key against it
    const approver = await findPairing({ ...w.options, qr: fresh.qr });
    w.server.onGet = (body) => {
      if (body.publicKey) body.publicKey = other;
    };
    fresh.number().catch(() => {});
    expect(await pairingErrorOf(approver.number())).toBe("tampered");
    fresh.cancel();
  });

  it("a sealed blob from another ephemeral key does not open", async () => {
    const w = await world();
    const fresh = await startPairing(w.options);
    const approver = await findPairing({ ...w.options, code: fresh.code });
    await Promise.all([fresh.number(), approver.number()]);
    const newKey = fromBase64Url(w.server.rows.get(fresh.id)?.publicKey as string);
    // the server hands over the right DK, sealed under a key that is not the pinned approver key
    const forged = toBase64Url(
      await sealToDevice(newKey, { kind: "device", userId: w.userId, keyV: 2 }, w.dataKey),
    );
    w.server.onPickup = (body) => {
      body.sealed = forged;
    };
    const finished = fresh.finish();
    approver.approve().catch(() => {});
    expect(await pairingErrorOf(finished)).toBe("tampered");
    expect(w.server.wraps.filter((x) => x.kind === "device")).toHaveLength(1);
  });

  it("a code is normalised", async () => {
    const w = await world();
    const fresh = await startPairing(w.options);
    (w.server.rows.get(fresh.id) as Row).code = "ABCDEFGH";
    const approver = await findPairing({ ...w.options, code: " abcd efgh " });
    expect(w.server.log).toContain("GET /api/v2/pairing?code=ABCDEFGH");
    approver.cancel();

    // a code that cannot be one is refused before any request; so is an unknown code
    const before = w.server.log.length;
    expect(await pairingErrorOf(findPairing({ ...w.options, code: "ABCD-EFGU" }))).toBe("bad_code");
    expect(await pairingErrorOf(findPairing({ ...w.options, code: "ABC" }))).toBe("bad_code");
    expect(w.server.log.length).toBe(before);
    expect(await pairingErrorOf(findPairing({ ...w.options, code: "ZZZZZZZZ" }))).toBe("bad_code");

    // a QR that is not exactly `wambito://pair?id=<id>&key=<key>` is refused too
    const key = fresh.qr.split("&key=")[1] as string;
    for (const qr of [
      `https://wambito.com/pair?id=${fresh.id}&key=${key}`,
      `wambito://pair?id=${fresh.id}`,
      `wambito://pair?key=${key}&id=${fresh.id}`,
      `wambito://pair?id=${fresh.id}&key=${key.slice(0, 40)}`,
      `wambito://pair?id=not-an-id&key=${key}`,
      `${fresh.qr}&x=1`,
    ]) {
      expect(await pairingErrorOf(findPairing({ ...w.options, qr }))).toBe("bad_code");
    }
    fresh.cancel();
  });

  it("404 or expiresAt passing is expired on both sides", async () => {
    // the row goes (404)
    const w = await world();
    const fresh = await startPairing(w.options);
    const approver = await findPairing({ ...w.options, code: fresh.code });
    w.server.rows.clear();
    expect(await pairingErrorOf(fresh.number())).toBe("expired");
    expect(await pairingErrorOf(fresh.finish())).toBe("expired");
    expect(await pairingErrorOf(approver.number())).toBe("expired");
    await expect(approver.approve()).rejects.toThrow("approve before number");

    // the clock passes expiresAt while the server still answers: both stop by themselves
    const v = await world();
    v.server.ignoreExpiry = true;
    const lonely = await startPairing(v.options);
    expect(await pairingErrorOf(lonely.number())).toBe("expired");
    const polls = v.server.log.filter((l) => l === `GET /api/v2/pairing/${lonely.id}`).length;
    expect(polls).toBeGreaterThan(100);
    expect(polls).toBeLessThanOrEqual(TTL / 1500 + 1);

    const late = await startPairing(v.options);
    const waiting = await findPairing({ ...v.options, code: late.code });
    // the new device never reveals: the approver waits until expiresAt
    expect(await pairingErrorOf(waiting.number())).toBe("expired");
    late.cancel();
  });

  it("approve() takes DK from this browser's device wrap, seals with keyV, and zeroes DK", async () => {
    const w = await world();
    const fresh = await startPairing(w.options);
    const approver = await findPairing({ ...w.options, code: fresh.code });
    const approverKey = () => w.server.rows.get(fresh.id)?.approverKey;
    await Promise.all([fresh.number(), approver.number()]);
    const pinned = approverKey();
    const sealedAt: string[] = [];
    w.server.onGet = (body) => {
      if (body.sealed) sealedAt.push(body.sealed as string);
    };
    await Promise.all([fresh.finish(), approver.approve()]);

    expect(handed.seals).toHaveLength(2); // the approver's seal, then the new device's own wrap
    const seal = handed.seals[0];
    expect(seal?.ctx).toEqual({ kind: "device", userId: w.userId, keyV: 2 });
    expect(seal?.ephemeral).toBe(true);
    // the sealed blob starts with the approver key the server stored
    expect(toBase64Url(fromBase64Url(sealedAt[0] as string).slice(0, 32))).toBe(pinned);
    // DK came from this browser's device wrap and is zeroed after the seal
    expect(handed.openedDevice).toHaveLength(1);
    expect(handed.openedDevice[0]).toBe(seal?.dataKey);
    expect(handed.openedDevice[0]?.every((x) => x === 0)).toBe(true);
    expect(w.server.log).toContain(`POST /api/v2/pairing/${fresh.id}/seal`);
  });

  it("cancel() stops polling", async () => {
    const w = await world();
    w.server.ignoreExpiry = true;
    const fresh = await startPairing(w.options);
    const number = fresh.number();
    await ticks(5);
    fresh.cancel();
    expect(await pairingErrorOf(number)).toBe("cancelled");
    const after = w.server.log.length;
    await ticks(20);
    expect(w.server.log.length).toBe(after);
    expect(await pairingErrorOf(fresh.finish())).toBe("cancelled");

    const again = await startPairing(w.options);
    const approver = await findPairing({ ...w.options, code: again.code });
    const waiting = approver.number();
    await ticks(5);
    approver.cancel();
    expect(await pairingErrorOf(waiting)).toBe("cancelled");
    const then = w.server.log.length;
    await ticks(20);
    expect(w.server.log.length).toBe(then);
    await expect(approver.approve()).rejects.toThrow("approve before number");
    again.cancel();
  });

  it("approve() before number() rejects and no seal request is made", async () => {
    const w = await world();
    const fresh = await startPairing(w.options);
    const approver = await findPairing({ ...w.options, code: fresh.code });
    // the new device reveals; the approver's number is ready but was never asked for
    await fresh.number();
    await expect(approver.approve()).rejects.toThrow("approve before number");
    await expect(approver.approve()).rejects.not.toBeInstanceOf(PairingError);
    await ticks(10);
    expect(w.server.log.some((l) => l.endsWith("/seal"))).toBe(false);
    expect(w.server.log.some((l) => l === "GET /api/v2/keys")).toBe(false);
    expect(handed.openedDevice).toHaveLength(0);

    // once the number was shown, the same object approves
    await approver.number();
    await Promise.all([fresh.finish(), approver.approve()]);
    expect(w.server.rows.size).toBe(0);
  });

  it("a relay whose expiresAt is far in the future still ends both sides after 10 minutes", async () => {
    const w = await world();
    w.server.ttl = 365 * 24 * 60 * 60 * 1000;
    const start = w.clock.t;
    const fresh = await startPairing(w.options);
    expect(await pairingErrorOf(fresh.number())).toBe("expired");
    expect(w.clock.t - start).toBeGreaterThanOrEqual(TTL);
    expect(w.clock.t - start).toBeLessThan(TTL + 2 * 1500);

    const late = await startPairing(w.options);
    const lookup = w.clock.t;
    const approver = await findPairing({ ...w.options, code: late.code });
    // the new device never reveals: the approver stops 10 minutes after its lookup
    expect(await pairingErrorOf(approver.number())).toBe("expired");
    expect(w.clock.t - lookup).toBeGreaterThanOrEqual(TTL);
    expect(w.clock.t - lookup).toBeLessThan(TTL + 2 * 1500);
    late.cancel();
  });
});
