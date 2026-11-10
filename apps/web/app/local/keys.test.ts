import "fake-indexeddb/auto";
import {
  deriveRecordKeys,
  formatRecoveryKey,
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  openFromDevice,
  openRecord,
  parseRecoveryKey,
  sealRecord,
  sealToDevice,
  toBase64Url,
  unwrapDataKey,
  verifyDeviceAttestation,
} from "@wambito/crypto";
import { describe, expect, it, vi } from "vitest";
import { createEncryptedStore } from "./encrypted-store.ts";

/** Every recovery secret `parseRecoveryKey` handed out, to check that unlock zeroes it. */
const parsedSecrets = vi.hoisted(() => [] as Uint8Array[]);
vi.mock("@wambito/crypto", async (original) => {
  const crypto = await original<typeof import("@wambito/crypto")>();
  return {
    ...crypto,
    parseRecoveryKey: (text: string) => {
      const secret = crypto.parseRecoveryKey(text);
      parsedSecrets.push(secret);
      return secret;
    },
  };
});

import {
  dropKeyVersion,
  forgetDevice,
  KeysError,
  type LocalKeys,
  loadLocalKeys,
  prepareAccount,
  refreshKeys,
  unlockWithRecovery,
  withDataKey,
} from "./keys.ts";

/** The record keys of the keyring's current version. */
const currentKeys = (local: LocalKeys | null) =>
  local!.keyring.byVersion.get(local!.keyring.current)!;

/** Prepares and commits at once, as the setup screen does once the person confirmed the key. */
async function setUpAccount(options: Parameters<typeof prepareAccount>[0]) {
  const prepared = await prepareAccount(options);
  await prepared.commit();
  return { recoveryKey: prepared.recoveryKey };
}

interface Wrap {
  id: string;
  kind: string;
  ref: string | null;
  keyV: number;
  wrapped: string;
  publicKey: string | null;
  attestation: string | null;
  label: string | null;
}

/** A fake `/v2/keys` that enforces the rules the tests care about (the real one: `routes/keys.ts`). */
function fakeKeys() {
  const wraps: Wrap[] = [];
  const puts: Array<{ id: string; kind: string; ifNoneMatch: string | null }> = [];
  const fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input), "http://x");
    const json = (body: unknown, status = 200) =>
      new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      });
    if (url.pathname === "/api/v2/keys" && (init?.method ?? "GET") === "GET")
      return json({ wraps });
    const match = /^\/api\/v2\/keys\/([0-9a-f-]{36})$/.exec(url.pathname);
    if (match && init?.method === "PUT") {
      const id = match[1] as string;
      expect(id).toBe(id.toLowerCase());
      const body = JSON.parse(String(init.body));
      const ifNoneMatch = new Headers(init.headers).get("if-none-match");
      puts.push({ id, kind: body.kind, ifNoneMatch });
      if (ifNoneMatch === "*" && wraps.some((w) => w.id !== id)) {
        return json({ code: "already_set_up" }, 409);
      }
      if (wraps.length === 0 && body.kind !== "recovery") {
        return json({ code: "recovery_required" }, 422);
      }
      if (body.kind === "device" && (!body.publicKey || !body.attestation)) {
        return json({ code: "attestation_required" }, 422);
      }
      const wrap: Wrap = {
        id,
        kind: body.kind,
        ref: body.ref ?? null,
        keyV: body.keyV,
        wrapped: body.wrapped,
        publicKey: body.publicKey ?? null,
        attestation: body.attestation ?? null,
        label: body.label ?? null,
      };
      const at = wraps.findIndex(
        (w) => w.id === id || (w.kind === "recovery" && body.kind === "recovery"),
      );
      if (at >= 0) wraps.splice(at, 1);
      wraps.push(wrap);
      return json(wrap);
    }
    return new Response(null, { status: 404 });
  };
  return { fetch: fetch as typeof globalThis.fetch, wraps, puts };
}

let counter = 0;
const newUser = () => `user_${++counter}`;
const REC = "01930000-0000-7000-8000-00000000000a";
const CTX = (userId: string, id: string) => ({ userId, type: "category" as const, id, keyV: 1 });

describe("prepareAccount then commit", () => {
  it("puts the recovery wrap first, then an attested device wrap, and keeps only derived keys", async () => {
    const api = fakeKeys();
    const userId = newUser();
    const { recoveryKey } = await setUpAccount({ userId, guest: false, fetch: api.fetch });

    expect(api.puts.map((p) => p.kind)).toEqual(["recovery", "device"]);
    expect(recoveryKey).toMatch(/^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$/);

    const recovery = api.wraps.find((w) => w.kind === "recovery");
    const device = api.wraps.find((w) => w.kind === "device");
    const dk = await unwrapDataKey(
      parseRecoveryKey(recoveryKey as string),
      { kind: "recovery", userId, keyV: 1 },
      fromBase64Url(recovery?.wrapped as string),
    );
    expect(device?.publicKey).not.toBeNull();
    expect(
      await verifyDeviceAttestation(
        dk,
        {
          userId,
          wrapId: device?.id as string,
          publicKey: fromBase64Url(device?.publicKey as string),
        },
        fromBase64Url(device?.attestation as string),
      ),
    ).toBe(true);

    const local = await loadLocalKeys(userId);
    expect(local?.keyring.current).toBe(1);
    expect(currentKeys(local).record.extractable).toBe(false);
    expect(currentKeys(local).dedupe.extractable).toBe(false);
    // the stored keys are the ones the data key derives
    const sealed = await sealRecord(currentKeys(local), CTX(userId, REC), { s: 1 });
    expect(sealed.length).toBeGreaterThan(0);
    const store = await createEncryptedStore(userId);
    const priv = await store.getKey("device");
    expect(priv).toBeDefined();
    expect(
      await openFromDevice(
        priv as never,
        { kind: "device", userId, keyV: 1 },
        fromBase64Url(device?.wrapped as string),
      ),
    ).toEqual(dk);
    expect(await store.getKey("dk")).toBeUndefined();
    store.close();
  });

  it("gives a guest keys and wraps but no recovery key", async () => {
    const api = fakeKeys();
    const userId = newUser();
    const result = await setUpAccount({ userId, guest: true, fetch: api.fetch });
    expect(result.recoveryKey).toBeNull();
    expect(await loadLocalKeys(userId)).not.toBeNull();
    expect(api.puts.map((p) => p.kind)).toEqual(["recovery", "device"]);
  });

  it("throws already_set_up when the account has wraps, and stores nothing", async () => {
    const api = fakeKeys();
    const userId = newUser();
    await setUpAccount({ userId, guest: false, fetch: api.fetch });
    const other = newUser();
    api.wraps.length = 0;
    await setUpAccount({ userId: other, guest: false, fetch: api.fetch });
    const second = await setUpAccount({ userId: other, guest: false, fetch: api.fetch }).catch(
      (e) => e,
    );
    expect(second).toBeInstanceOf(KeysError);
    expect(second.code).toBe("already_set_up");
  });
});

describe("prepareAccount", () => {
  it("sends and stores nothing until commit()", async () => {
    const api = fakeKeys();
    const userId = newUser();
    const prepared = await prepareAccount({ userId, guest: false, fetch: api.fetch });
    expect(prepared.recoveryKey).toMatch(/^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$/);
    expect(api.puts).toEqual([]);
    expect(await loadLocalKeys(userId)).toBeNull();

    const keys = await prepared.commit();
    expect(api.puts.map((p) => p.kind)).toEqual(["recovery", "device"]);
    expect(keys.keyring.current).toBe(1);
    expect(await loadLocalKeys(userId)).not.toBeNull();
  });

  it("a prepared key that is never committed leaves the account without wraps", async () => {
    const api = fakeKeys();
    const userId = newUser();
    await prepareAccount({ userId, guest: false, fetch: api.fetch });
    expect(api.wraps).toEqual([]);
    // so the next visit prepares again (with a new key) instead of asking for Unlock
    const again = await prepareAccount({ userId, guest: false, fetch: api.fetch });
    expect(again.recoveryKey).not.toBeNull();
  });

  it("is retry-safe: a failed device PUT is sent again with the same ids", async () => {
    const api = fakeKeys();
    const userId = newUser();
    let failDevice = true;
    const flaky = (async (input: RequestInfo | URL, init?: RequestInit) => {
      if (failDevice && init?.method === "PUT" && String(init.body).includes('"device"')) {
        throw new TypeError("offline");
      }
      return api.fetch(input, init);
    }) as typeof globalThis.fetch;
    const prepared = await prepareAccount({ userId, guest: false, fetch: flaky });
    const err = await prepared.commit().catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("offline");
    expect(await loadLocalKeys(userId)).toBeNull();
    expect(api.wraps.map((w) => w.kind)).toEqual(["recovery"]);
    const recoveryId = api.wraps[0]?.id;

    failDevice = false;
    await prepared.commit();
    expect(api.wraps.map((w) => w.kind).sort()).toEqual(["device", "recovery"]);
    expect(api.wraps.find((w) => w.kind === "recovery")?.id).toBe(recoveryId);
    expect(await loadLocalKeys(userId)).not.toBeNull();

    // the wrap the server kept is the one the shown key opens
    const recovery = api.wraps.find((w) => w.kind === "recovery");
    await expect(
      unwrapDataKey(
        parseRecoveryKey(prepared.recoveryKey as string),
        { kind: "recovery", userId, keyV: 1 },
        fromBase64Url(recovery?.wrapped as string),
      ),
    ).resolves.toBeInstanceOf(Uint8Array);
  });

  it("a second commit() after success sends nothing", async () => {
    const api = fakeKeys();
    const userId = newUser();
    const prepared = await prepareAccount({ userId, guest: false, fetch: api.fetch });
    const first = await prepared.commit();
    const puts = api.puts.length;
    const second = await prepared.commit();
    expect(api.puts.length).toBe(puts);
    expect(second.keyring.current).toBe(first.keyring.current);
  });
});

describe("two setups at once", () => {
  it("sends the first recovery wrap create-only (If-None-Match: *), the device wrap plainly", async () => {
    const api = fakeKeys();
    await setUpAccount({ userId: newUser(), guest: false, fetch: api.fetch });
    expect(api.puts.map((p) => [p.kind, p.ifNoneMatch])).toEqual([
      ["recovery", "*"],
      ["device", null],
    ]);
  });

  it("the setup that loses the race throws already_set_up and keeps nothing", async () => {
    const api = fakeKeys();
    const userId = newUser();
    const first = await prepareAccount({ userId, guest: false, fetch: api.fetch });
    const second = await prepareAccount({ userId, guest: false, fetch: api.fetch });
    await first.commit();
    await forgetDevice(userId);
    const err = await second.commit().catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("already_set_up");
    expect(api.wraps.map((w) => w.kind).sort()).toEqual(["device", "recovery"]);
    expect(await loadLocalKeys(userId)).toBeNull();
  });
});

describe("a browser without X25519 in WebCrypto", () => {
  // The noble fallback keeps the device private key as raw bytes: never stored on the web.
  const rawKeyPair = async () => ({
    publicKey: new Uint8Array(32).fill(1),
    privateKey: { kind: "noble-x25519" as const, raw: new Uint8Array(32).fill(2) },
  });

  it("refuses to set up with unsupported_browser, before any request", async () => {
    const api = fakeKeys();
    const calls: string[] = [];
    const spy = (async (input: RequestInfo | URL, init?: RequestInit) => {
      calls.push(String(input));
      return api.fetch(input, init);
    }) as typeof globalThis.fetch;
    const userId = newUser();
    const err = await prepareAccount({
      userId,
      guest: false,
      fetch: spy,
      deviceKeyPair: rawKeyPair,
    }).catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("unsupported_browser");
    expect(calls).toEqual([]);
    expect(await loadLocalKeys(userId)).toBeNull();
  });

  it("refuses to unlock with unsupported_browser, and sends no wrap", async () => {
    const api = fakeKeys();
    const userId = newUser();
    const { recoveryKey } = await setUpAccount({ userId, guest: false, fetch: api.fetch });
    await forgetDevice(userId);
    const puts = api.puts.length;
    const err = await unlockWithRecovery({
      userId,
      text: recoveryKey as string,
      fetch: api.fetch,
      deviceKeyPair: rawKeyPair,
    }).catch((e) => e);
    expect(err.code).toBe("unsupported_browser");
    expect(api.puts.length).toBe(puts);
    expect(await loadLocalKeys(userId)).toBeNull();
  });
});

describe("loadLocalKeys", () => {
  it("is null in a browser that was never set up", async () => {
    expect(await loadLocalKeys(newUser())).toBeNull();
  });
});

describe("unlockWithRecovery", () => {
  async function accountWithKey() {
    const api = fakeKeys();
    const userId = newUser();
    const { recoveryKey } = await setUpAccount({ userId, guest: false, fetch: api.fetch });
    await forgetDevice(userId);
    return { api, userId, recoveryKey: recoveryKey as string };
  }

  it("opens the recovery wrap, adds a device wrap and stores the same record key", async () => {
    const { api, userId, recoveryKey } = await accountWithKey();
    expect(await loadLocalKeys(userId)).toBeNull();
    const before = api.wraps.length;
    // tolerant of case, spaces and dashes
    const messy = ` ${recoveryKey.toLowerCase().replaceAll("-", "  ")} `;
    const keys = await unlockWithRecovery({ userId, text: messy, fetch: api.fetch });
    expect(keys.keyring.current).toBe(1);
    expect(api.wraps.length).toBe(before + 1);
    expect(api.wraps.filter((w) => w.kind === "device").length).toBe(2);
    const sealed = await sealRecord(currentKeys(keys), CTX(userId, REC), { s: 1 });
    expect(
      await openRecord(currentKeys(await loadLocalKeys(userId)), CTX(userId, REC), sealed),
    ).toEqual({ s: 1 });
  });

  it("rejects a malformed key with bad_recovery_key before any request", async () => {
    const { api, userId, recoveryKey } = await accountWithKey();
    const puts = api.puts.length;
    const typo = recoveryKey.slice(0, -1) + (recoveryKey.endsWith("0") ? "1" : "0");
    for (const text of ["", "hello", typo]) {
      const err = await unlockWithRecovery({ userId, text, fetch: api.fetch }).catch((e) => e);
      expect(err.code).toBe("bad_recovery_key");
    }
    expect(api.puts.length).toBe(puts);
  });

  it("zeroes the recovery secret once done, whatever the outcome", async () => {
    const { api, userId, recoveryKey } = await accountWithKey();
    parsedSecrets.length = 0;
    await unlockWithRecovery({ userId, text: recoveryKey, fetch: api.fetch });
    await forgetDevice(userId);
    const stranger = formatRecoveryKey(crypto.getRandomValues(new Uint8Array(16)));
    await unlockWithRecovery({ userId, text: stranger, fetch: api.fetch }).catch(() => {});
    expect(parsedSecrets).toHaveLength(2);
    for (const secret of parsedSecrets) expect(secret.every((b) => b === 0)).toBe(true);
  });

  it("rejects a well-formed key of another account with wrong_recovery_key", async () => {
    const { api, userId } = await accountWithKey();
    const stranger = formatRecoveryKey(crypto.getRandomValues(new Uint8Array(16)));
    const err = await unlockWithRecovery({ userId, text: stranger, fetch: api.fetch }).catch(
      (e) => e,
    );
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("wrong_recovery_key");
    expect(await loadLocalKeys(userId)).toBeNull();
  });
});

describe("forgetDevice", () => {
  it("removes the keys", async () => {
    const api = fakeKeys();
    const userId = newUser();
    await setUpAccount({ userId, guest: false, fetch: api.fetch });
    await forgetDevice(userId);
    expect(await loadLocalKeys(userId)).toBeNull();
  });
});

describe("the signed-in account", () => {
  it("every /v2/keys call names the vault's account", async () => {
    const api = fakeKeys();
    const userId = newUser();
    const seen: Array<string | null> = [];
    const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      seen.push(new Headers(init?.headers).get("x-wambito-user"));
      return api.fetch(input, init);
    }) as typeof globalThis.fetch;
    await setUpAccount({ userId, guest: false, fetch });
    expect(seen.length).toBeGreaterThan(1);
    expect(seen.every((v) => v === userId)).toBe(true);
  });

  it("409 session_changed throws session_changed and stores nothing", async () => {
    const userId = newUser();
    const fetch = (async () =>
      new Response(JSON.stringify({ code: "session_changed" }), {
        status: 409,
        headers: { "content-type": "application/json" },
      })) as typeof globalThis.fetch;
    await expect(prepareAccount({ userId, guest: false, fetch })).rejects.toMatchObject({
      code: "session_changed",
      status: 409,
    });
    expect(await loadLocalKeys(userId)).toBeNull();
  });
});

/** An account set up in this browser, with its DK (from the recovery wrap) for checks. */
async function enrolledAccount() {
  const api = fakeKeys();
  const userId = newUser();
  const { recoveryKey } = await setUpAccount({ userId, guest: false, fetch: api.fetch });
  const recovery = api.wraps.find((w) => w.kind === "recovery") as Wrap;
  const dk = await unwrapDataKey(
    parseRecoveryKey(recoveryKey as string),
    { kind: "recovery", userId, keyV: 1 },
    fromBase64Url(recovery.wrapped),
  );
  const device = api.wraps.find((w) => w.kind === "device") as Wrap;
  return { api, userId, dk, device };
}

describe("the device wrap", () => {
  it("enroll keeps the device wrap id and public key", async () => {
    const { userId, device } = await enrolledAccount();
    const store = await createEncryptedStore(userId);
    expect(await store.getMeta("deviceWrapId")).toBe(device.id);
    expect(await store.getMeta("devicePublicKey")).toBe(device.publicKey);
    store.close();
  });

  it("enroll labels the wrap after this browser", async () => {
    const { device } = await enrolledAccount();
    expect(typeof device.label).toBe("string");
    expect(device.label?.length).toBeGreaterThan(0);
  });
});

describe("the keyring", () => {
  it("a 2a vault's keys load as version keyV and move to the versioned names", async () => {
    const userId = newUser();
    const keys = await deriveRecordKeys(generateDataKey(), false);
    const store = await createEncryptedStore(userId);
    await store.putKey("record", keys.record);
    await store.putKey("dedupe", keys.dedupe);
    await store.setMeta("keyV", 3);
    await store.setMeta("userId", userId);

    const local = await loadLocalKeys(userId);
    expect(local?.keyring.current).toBe(3);
    expect([...(local?.keyring.byVersion.keys() ?? [])]).toEqual([3]);
    const sealed = await sealRecord(keys, { ...CTX(userId, REC), keyV: 3 }, { s: 1 });
    expect(await openRecord(currentKeys(local), { ...CTX(userId, REC), keyV: 3 }, sealed)).toEqual({
      s: 1,
    });
    expect(await store.getKey("record")).toBeUndefined();
    expect(await store.getKey("dedupe")).toBeUndefined();
    expect(await store.getKey("record:3")).toBeDefined();
    expect(await store.getKey("dedupe:3")).toBeDefined();
    // and loads the same again under the new names
    expect((await loadLocalKeys(userId))?.keyring.current).toBe(3);
    store.close();
  });

  it("dropKeyVersion removes record:1 and dedupe:1 only", async () => {
    const { api, userId, device } = await enrolledAccount();
    await rotateDeviceWrap(api, userId, device, generateDataKey(), 2);
    await refreshKeys({ userId, fetch: api.fetch });

    await dropKeyVersion(userId, 1);
    const store = await createEncryptedStore(userId);
    expect(await store.getKey("record:1")).toBeUndefined();
    expect(await store.getKey("dedupe:1")).toBeUndefined();
    expect(await store.getKey("record:2")).toBeDefined();
    expect(await store.getKey("dedupe:2")).toBeDefined();
    expect(await store.getKey("device")).toBeDefined();
    store.close();
    const local = await loadLocalKeys(userId);
    expect(local?.keyring.current).toBe(2);
    expect([...(local?.keyring.byVersion.keys() ?? [])]).toEqual([2]);
  });
});

/** The server re-wrapped a new DK to this browser's public key under `keyV` (a rotation). */
async function rotateDeviceWrap(
  api: ReturnType<typeof fakeKeys>,
  userId: string,
  device: Wrap,
  dk: Uint8Array,
  keyV: number,
) {
  const wrap = api.wraps.find((w) => w.id === device.id) as Wrap;
  wrap.keyV = keyV;
  wrap.wrapped = toBase64Url(
    await sealToDevice(
      fromBase64Url(device.publicKey as string),
      { kind: "device", userId, keyV },
      dk,
    ),
  );
}

describe("withDataKey", () => {
  it("withDataKey opens this browser's device wrap and zeroes DK after", async () => {
    const { api, userId, dk } = await enrolledAccount();
    let seen: Uint8Array | undefined;
    let copy: Uint8Array | undefined;
    const result = await withDataKey({ userId, fetch: api.fetch }, async (key, keyV) => {
      seen = key;
      copy = key.slice();
      return keyV;
    });
    expect(result).toBe(1);
    expect(copy).toEqual(dk);
    expect(seen?.every((b) => b === 0)).toBe(true);
  });

  it("zeroes DK when fn throws too", async () => {
    const { api, userId } = await enrolledAccount();
    let seen: Uint8Array | undefined;
    const err = await withDataKey({ userId, fetch: api.fetch }, async (key) => {
      seen = key;
      throw new Error("boom");
    }).catch((e) => e);
    expect(err.message).toBe("boom");
    expect(seen?.every((b) => b === 0)).toBe(true);
  });

  it("withDataKey throws device_removed when no device wrap has this browser's id", async () => {
    const { api, userId, device } = await enrolledAccount();
    api.wraps.splice(
      api.wraps.findIndex((w) => w.id === device.id),
      1,
    );
    const fn = vi.fn(async () => 1);
    await expect(withDataKey({ userId, fetch: api.fetch }, fn)).rejects.toMatchObject({
      code: "device_removed",
    });
    expect(fn).not.toHaveBeenCalled();
  });

  it("a 2a browser without the wrap id finds its device wrap and remembers it", async () => {
    const { api, userId, dk, device } = await enrolledAccount();
    // a second device wrap that is not this browser's
    const other = await generateDeviceKeyPair();
    api.wraps.unshift({
      ...device,
      id: "01930000-0000-7000-8000-0000000000ff",
      ref: "01930000-0000-7000-8000-0000000000ff",
      publicKey: toBase64Url(other.publicKey),
      wrapped: toBase64Url(
        await sealToDevice(other.publicKey, { kind: "device", userId, keyV: 1 }, dk),
      ),
    });
    const store = await createEncryptedStore(userId);
    await store.setMeta("deviceWrapId", undefined);
    await store.setMeta("devicePublicKey", undefined);

    let copy: Uint8Array | undefined;
    await withDataKey({ userId, fetch: api.fetch }, async (key) => {
      copy = key.slice();
    });
    expect(copy).toEqual(dk);
    expect(await store.getMeta("deviceWrapId")).toBe(device.id);
    expect(await store.getMeta("devicePublicKey")).toBe(device.publicKey);
    store.close();
  });
});

describe("refreshKeys", () => {
  it("refreshKeys adds the new version and keeps the old one", async () => {
    const { api, userId, device } = await enrolledAccount();
    const next = generateDataKey();
    await rotateDeviceWrap(api, userId, device, next, 2);

    const local = await refreshKeys({ userId, fetch: api.fetch });
    expect(local.keyring.current).toBe(2);
    expect([...local.keyring.byVersion.keys()].sort()).toEqual([1, 2]);
    const ctx2 = { ...CTX(userId, REC), keyV: 2 };
    const sealed = await sealRecord(await deriveRecordKeys(next, false), ctx2, { s: 2 });
    expect(await openRecord(currentKeys(local), ctx2, sealed)).toEqual({ s: 2 });

    const again = await loadLocalKeys(userId);
    expect(again?.keyring.current).toBe(2);
    expect([...(again?.keyring.byVersion.keys() ?? [])].sort()).toEqual([1, 2]);
  });

  it("a replayed lower-version wrap leaves current and the stored keys unchanged", async () => {
    const { api, userId, dk, device } = await enrolledAccount();
    const next = generateDataKey();
    await rotateDeviceWrap(api, userId, device, next, 2);
    await refreshKeys({ userId, fetch: api.fetch });
    // the server replays the old keyV 1 wrap (it opens: it is sealed to this browser)
    await rotateDeviceWrap(api, userId, device, generateDataKey(), 1);

    const local = await refreshKeys({ userId, fetch: api.fetch });
    expect(local.keyring.current).toBe(2);
    const store = await createEncryptedStore(userId);
    expect(await store.getMeta("keyV")).toBe(2);
    store.close();
    const again = await loadLocalKeys(userId);
    expect(again?.keyring.current).toBe(2);
    for (const [v, key] of [
      [1, dk],
      [2, next],
    ] as const) {
      const ctx = { ...CTX(userId, REC), keyV: v };
      const sealed = await sealRecord(await deriveRecordKeys(key, false), ctx, { v });
      expect(await openRecord(again!.keyring.byVersion.get(v)!, ctx, sealed)).toEqual({ v });
    }
  });

  it("a same-version wrap under another DK does not overwrite record:<v>", async () => {
    const { api, userId, dk, device } = await enrolledAccount();
    await rotateDeviceWrap(api, userId, device, generateDataKey(), 1);

    const local = await refreshKeys({ userId, fetch: api.fetch });
    expect(local.keyring.current).toBe(1);
    const ctx = CTX(userId, REC);
    const sealed = await sealRecord(await deriveRecordKeys(dk, false), ctx, { s: 1 });
    expect(await openRecord(currentKeys(local), ctx, sealed)).toEqual({ s: 1 });
    expect(await openRecord(currentKeys(await loadLocalKeys(userId)), ctx, sealed)).toEqual({
      s: 1,
    });
  });

  it("refreshKeys refuses a device wrap whose public key is not this browser's", async () => {
    const { api, userId, device } = await enrolledAccount();
    const other = await generateDeviceKeyPair();
    const wrap = api.wraps.find((w) => w.id === device.id) as Wrap;
    wrap.publicKey = toBase64Url(other.publicKey);
    await expect(refreshKeys({ userId, fetch: api.fetch })).rejects.toMatchObject({
      code: "device_removed",
    });
    expect((await loadLocalKeys(userId))?.keyring.current).toBe(1);
  });
});
