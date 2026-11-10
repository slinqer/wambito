import "fake-indexeddb/auto";
import {
  deriveRecordKeys,
  deviceAttestation,
  formatRecoveryKey,
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  openFromDevice,
  openKeyLink,
  openRecord,
  parseRecoveryKey,
  sealKeyLink,
  sealRecord,
  sealToDevice,
  toBase64Url,
  unwrapDataKey,
  verifyDeviceAttestation,
  wrapDataKey,
} from "@wambito/crypto";
import { describe, expect, it, vi } from "vitest";
import { createEncryptedStore } from "./encrypted-store.ts";
import { uuidv7 } from "./ids.ts";

/** Every secret and data key the crypto hands out, to check that rotation zeroes them. */
const handed = vi.hoisted(() => ({
  dataKeys: [] as Uint8Array[],
  opened: [] as Uint8Array[],
  unwrapped: [] as Uint8Array[],
  parsed: [] as Uint8Array[],
  secrets: [] as Uint8Array[],
}));
vi.mock("@wambito/crypto", async (original) => {
  const crypto = await original<typeof import("@wambito/crypto")>();
  const track =
    <A extends unknown[]>(list: Uint8Array[], fn: (...args: A) => Promise<Uint8Array>) =>
    async (...args: A) => {
      const out = await fn(...args);
      list.push(out);
      return out;
    };
  return {
    ...crypto,
    generateDataKey: () => {
      const dk = crypto.generateDataKey();
      handed.dataKeys.push(dk);
      return dk;
    },
    newRecoverySecret: () => {
      const secret = crypto.newRecoverySecret();
      handed.secrets.push(secret);
      return secret;
    },
    parseRecoveryKey: (text: string) => {
      const secret = crypto.parseRecoveryKey(text);
      handed.parsed.push(secret);
      return secret;
    },
    openFromDevice: track(handed.opened, crypto.openFromDevice),
    unwrapDataKey: track(handed.unwrapped, crypto.unwrapDataKey),
  };
});

import { KeysError, loadLocalKeys, prepareAccount } from "./keys.ts";
import { checkRecoveryKey, newRecoveryKey, rotateKeys } from "./rotate.ts";

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

/** A fake `/v2/keys` with the rules of `services/keys.ts` the tests care about, rotate included. */
function fakeKeys() {
  const state = {
    wraps: [] as Wrap[],
    puts: [] as Array<{ id: string; kind: string; keyV: number }>,
    rotations: [] as Array<{ keyV: number; wraps: Wrap[]; link?: string }>,
    /** Every `POST /v2/keys/rotate` body, kept before any check (refused ones too). */
    posts: [] as Array<{ keyV: number; link?: string }>,
    /** `link(v)` by the version whose key seals it, base64url, listed by `GET /v2/keys`. */
    links: new Map<number, string>(),
    /** Another device rotated first: the next rotate gets 409 `key_version_mismatch`. */
    rotatedElsewhere: false,
    /** The next rotate commits, then its answer is lost: the network is down from then on. */
    loseNextAnswer: false,
    /** The next PUT is kept, then its answer is lost (the network stays up). */
    losePutAnswer: false,
    offline: false,
  };
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
  const toWrap = (id: string, body: Record<string, unknown>): Wrap => ({
    id,
    kind: body.kind as string,
    ref: (body.ref as string | undefined) ?? null,
    keyV: body.keyV as number,
    wrapped: body.wrapped as string,
    publicKey: (body.publicKey as string | undefined) ?? null,
    attestation: (body.attestation as string | undefined) ?? null,
    label: (body.label as string | undefined) ?? null,
  });
  const current = () => Math.max(0, ...state.wraps.map((w) => w.keyV));
  const fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    if (state.offline) throw new TypeError("offline");
    const response = await answer(input, init);
    if (state.loseNextAnswer && String(input).endsWith("/v2/keys/rotate") && response.ok) {
      state.loseNextAnswer = false;
      state.offline = true;
      throw new TypeError("offline");
    }
    if (state.losePutAnswer && init?.method === "PUT" && response.ok) {
      state.losePutAnswer = false;
      throw new TypeError("offline");
    }
    return response;
  };
  const answer = async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input), "http://x");
    const method = init?.method ?? "GET";
    if (url.pathname === "/api/v2/keys" && method === "GET")
      return json({
        wraps: state.wraps,
        links: [...state.links].sort(([x], [y]) => x - y).map(([keyV, link]) => ({ keyV, link })),
      });
    if (url.pathname === "/api/v2/keys/rotate" && method === "POST") {
      const body = JSON.parse(String(init?.body)) as {
        keyV: number;
        wraps: Array<Record<string, unknown>>;
        link?: string;
      };
      state.posts.push({ keyV: body.keyV, link: body.link });
      if (state.rotatedElsewhere || body.keyV !== current() + 1) {
        return json({ code: "key_version_mismatch" }, 409);
      }
      if (body.wraps.filter((w) => w.kind === "recovery").length !== 1) {
        return json({ code: "recovery_required" }, 422);
      }
      if (body.wraps.some((w) => w.kind === "device" && (!w.publicKey || !w.attestation))) {
        return json({ code: "attestation_required" }, 422);
      }
      const wraps = body.wraps.map((w) => {
        expect(w.keyV).toBe(body.keyV);
        return toWrap(w.id as string, w);
      });
      state.rotations.push({ keyV: body.keyV, wraps, link: body.link });
      state.wraps.splice(0, state.wraps.length, ...wraps);
      return json({ wraps });
    }
    const match = /^\/api\/v2\/keys\/([0-9a-f-]{36})$/.exec(url.pathname);
    if (match && method === "PUT") {
      const id = match[1] as string;
      const body = JSON.parse(String(init?.body));
      if (state.wraps.length > 0 && body.keyV !== current()) {
        return json({ code: "key_version_mismatch" }, 409);
      }
      state.puts.push({ id, kind: body.kind, keyV: body.keyV });
      const at = state.wraps.findIndex(
        (w) => w.id === id || (w.kind === "recovery" && body.kind === "recovery"),
      );
      if (at >= 0) state.wraps.splice(at, 1);
      state.wraps.push(toWrap(id, body));
      return json(state.wraps.at(-1));
    }
    return new Response(null, { status: 404 });
  };
  return Object.assign(state, { fetch: fetch as typeof globalThis.fetch });
}

let counter = 0;
const newUser = () => `rotate_user_${++counter}`;
const SETTINGS_ID = "01930000-0000-7000-8000-0000000000c1";

const clearHanded = () => {
  for (const list of Object.values(handed)) list.length = 0;
};

/** An account set up in this browser (keyV 1), its DK and recovery key, and settings. */
async function account(revokedDevices: string[] = []) {
  const api = fakeKeys();
  const userId = newUser();
  const prepared = await prepareAccount({ userId, guest: false, fetch: api.fetch });
  await prepared.commit();
  const recoveryKey = prepared.recoveryKey as string;
  const dk = await openRecovery(api, userId, recoveryKey, 1);
  const own = api.wraps.find((w) => w.kind === "device") as Wrap;
  const store = await createEncryptedStore(userId);
  await store.put("settings", SETTINGS_ID, {
    s: 1,
    name: null,
    currency: "EUR",
    locale: "es",
    timezone: "Europe/Madrid",
    onboardingCompletedAt: null,
    revokedDevices,
  });
  store.close();
  clearHanded();
  api.puts.length = 0;
  return { api, userId, recoveryKey, dk, own, options: { userId, fetch: api.fetch } };
}

type Account = Awaited<ReturnType<typeof account>>;

async function openRecovery(
  api: ReturnType<typeof fakeKeys>,
  userId: string,
  recoveryKey: string,
  keyV: number,
) {
  const wrap = api.wraps.find((w) => w.kind === "recovery") as Wrap;
  expect(wrap.keyV).toBe(keyV);
  return unwrapDataKey(
    parseRecoveryKey(recoveryKey),
    { kind: "recovery", userId, keyV },
    fromBase64Url(wrap.wrapped),
  );
}

/** Another device of the account, attested under `attestWith` (the account's DK by default). */
async function addDevice(a: Account, label: string, attestWith?: Uint8Array) {
  const pair = await generateDeviceKeyPair();
  const id = uuidv7();
  a.api.wraps.push({
    id,
    kind: "device",
    ref: id,
    keyV: 1,
    wrapped: toBase64Url(
      await sealToDevice(pair.publicKey, { kind: "device", userId: a.userId, keyV: 1 }, a.dk),
    ),
    publicKey: toBase64Url(pair.publicKey),
    attestation: toBase64Url(
      await deviceAttestation(attestWith ?? a.dk, {
        userId: a.userId,
        wrapId: id,
        publicKey: pair.publicKey,
      }),
    ),
    label,
  });
  clearHanded();
  return { id, pair, label };
}

async function addPasskey(a: Account, credentialId: string) {
  const prf = crypto.getRandomValues(new Uint8Array(32));
  const id = uuidv7();
  a.api.wraps.push({
    id,
    kind: "passkey",
    ref: credentialId,
    keyV: 1,
    wrapped: toBase64Url(
      await wrapDataKey(prf, { kind: "passkey", userId: a.userId, keyV: 1 }, a.dk),
    ),
    publicKey: null,
    attestation: null,
    label: "Passkey",
  });
  clearHanded();
  return { id, prf };
}

const wrapOf = (a: Account, id: string) => a.api.wraps.find((w) => w.id === id) as Wrap;

describe("rotateKeys", () => {
  it("a typed recovery key that does not open the current recovery wrap is wrong_recovery_key, before anything is made", async () => {
    const a = await account();
    const stranger = formatRecoveryKey(crypto.getRandomValues(new Uint8Array(16)));
    const err = await rotateKeys({
      ...a.options,
      remove: [],
      recovery: { text: stranger },
    }).catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("wrong_recovery_key");
    expect(handed.dataKeys).toEqual([]);
    expect(handed.opened).toEqual([]);
    expect(a.api.rotations).toEqual([]);
  });

  it("rotation keeps the other devices, sealed to their public keys with fresh attestations under the new DK, same ids and labels", async () => {
    const a = await account();
    const other = await addDevice(a, "Firefox on Linux");
    const otherBefore = { ...wrapOf(a, other.id) };
    const prepared = await rotateKeys({
      ...a.options,
      remove: [],
      recovery: { text: a.recoveryKey },
    });
    expect(prepared.recoveryKey).toBeNull();
    const result = await prepared.commit();
    expect(result).toEqual({ keyV: 2, dropped: [] });

    const newDk = await openRecovery(a.api, a.userId, a.recoveryKey, 2);
    expect(newDk).not.toEqual(a.dk);
    const store = await createEncryptedStore(a.userId);
    const ownPrivate = await store.getKey("device");
    store.close();
    for (const [device, privateKey] of [
      [a.own, ownPrivate],
      [otherBefore, other.pair.privateKey],
    ] as const) {
      const wrap = wrapOf(a, device.id);
      expect(wrap).toMatchObject({
        kind: "device",
        ref: device.id,
        keyV: 2,
        label: device.label,
        publicKey: device.publicKey,
      });
      expect(
        await openFromDevice(
          privateKey as never,
          { kind: "device", userId: a.userId, keyV: 2 },
          fromBase64Url(wrap.wrapped),
        ),
      ).toEqual(newDk);
      expect(
        await verifyDeviceAttestation(
          newDk,
          {
            userId: a.userId,
            wrapId: wrap.id,
            publicKey: fromBase64Url(wrap.publicKey as string),
          },
          fromBase64Url(wrap.attestation as string),
        ),
      ).toBe(true);
    }
    expect(wrapOf(a, other.id).label).toBe("Firefox on Linux");
    expect(a.api.wraps.filter((w) => w.kind === "device")).toHaveLength(2);
  });

  it("the removed ids and the settings' revokedDevices are left out, and reported", async () => {
    const revoked = uuidv7();
    const a = await account([revoked]);
    const gone = await addDevice(a, "Chrome on Android");
    const kept = await addDevice(a, "Safari on iOS");
    // the server still lists the revoked device (an old wrap kept by a malicious server)
    const old = await addDevice(a, "Edge on Windows");
    const oldWrap = wrapOf(a, old.id);
    oldWrap.id = revoked;
    oldWrap.ref = revoked;
    oldWrap.attestation = toBase64Url(
      await deviceAttestation(a.dk, {
        userId: a.userId,
        wrapId: revoked,
        publicKey: old.pair.publicKey,
      }),
    );

    const prepared = await rotateKeys({
      ...a.options,
      remove: [gone.id],
      recovery: { text: a.recoveryKey },
    });
    const result = await prepared.commit();
    expect(result.dropped).toEqual([
      { id: gone.id, label: "Chrome on Android", reason: "removed" },
      { id: revoked, label: "Edge on Windows", reason: "revoked" },
    ]);
    expect(
      a.api.wraps
        .filter((w) => w.kind === "device")
        .map((w) => w.id)
        .sort(),
    ).toEqual([a.own.id, kept.id].sort());
  });

  it("a device wrap whose attestation fails under the old DK is left out and reported as attestation", async () => {
    const a = await account();
    const forged = await addDevice(a, "Chrome on Linux", generateDataKey());
    const result = await (
      await rotateKeys({ ...a.options, remove: [], recovery: { text: a.recoveryKey } })
    ).commit();
    expect(result.dropped).toEqual([
      { id: forged.id, label: "Chrome on Linux", reason: "attestation" },
    ]);
    expect(a.api.wraps.some((w) => w.id === forged.id)).toBe(false);
  });

  it("{ fresh: true } shows a new key and sends nothing until commit", async () => {
    const a = await account();
    const before = JSON.stringify(a.api.wraps);
    const prepared = await rotateKeys({ ...a.options, remove: [], recovery: { fresh: true } });
    expect(prepared.recoveryKey).toMatch(/^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$/);
    expect(prepared.recoveryKey).not.toBe(a.recoveryKey);
    expect(a.api.rotations).toEqual([]);
    expect(a.api.puts).toEqual([]);
    expect(JSON.stringify(a.api.wraps)).toBe(before);
    expect((await loadLocalKeys(a.userId))?.keyring.current).toBe(1);

    await prepared.commit();
    const newDk = await openRecovery(a.api, a.userId, prepared.recoveryKey as string, 2);
    expect(newDk).toHaveLength(32);
    await expect(openRecovery(a.api, a.userId, a.recoveryKey, 2)).rejects.toThrow();
  });

  it("the touched passkey is re-wrapped; other passkeys lose their wrap", async () => {
    const a = await account();
    const touched = await addPasskey(a, "cred-touched");
    const other = await addPasskey(a, "cred-other");
    await (
      await rotateKeys({
        ...a.options,
        remove: [],
        recovery: { fresh: true },
        passkey: { credentialId: "cred-touched", prf: touched.prf.slice() },
      })
    ).commit();
    const passkeys = a.api.wraps.filter((w) => w.kind === "passkey");
    expect(passkeys.map((w) => [w.id, w.ref, w.label])).toEqual([
      [touched.id, "cred-touched", "Passkey"],
    ]);
    expect(a.api.wraps.some((w) => w.id === other.id)).toBe(false);
    const fromPasskey = await unwrapDataKey(
      touched.prf,
      { kind: "passkey", userId: a.userId, keyV: 2 },
      fromBase64Url(passkeys[0]?.wrapped as string),
    );
    const store = await createEncryptedStore(a.userId);
    const ownPrivate = await store.getKey("device");
    store.close();
    expect(
      await openFromDevice(
        ownPrivate as never,
        { kind: "device", userId: a.userId, keyV: 2 },
        fromBase64Url(wrapOf(a, a.own.id).wrapped),
      ),
    ).toEqual(fromPasskey);
  });

  it("after commit the keyring has the new version and settings.revokedDevices holds the removed ids", async () => {
    const earlier = uuidv7();
    const a = await account([earlier]);
    const gone = await addDevice(a, "Chrome on Android");
    await (
      await rotateKeys({ ...a.options, remove: [gone.id], recovery: { text: a.recoveryKey } })
    ).commit();

    const local = await loadLocalKeys(a.userId);
    expect(local?.keyring.current).toBe(2);
    expect([...(local?.keyring.byVersion.keys() ?? [])]).toEqual([1, 2]);
    // version 2's record keys are the new DK's
    const newDk = await openRecovery(a.api, a.userId, a.recoveryKey, 2);
    const ctx = { userId: a.userId, type: "settings" as const, id: SETTINGS_ID, keyV: 2 };
    const sealed = await sealRecord(await deriveRecordKeys(newDk, false), ctx, { s: 2 });
    expect(await openRecord(local?.keyring.byVersion.get(2) as never, ctx, sealed)).toEqual({
      s: 2,
    });

    const store = await createEncryptedStore(a.userId);
    const settings = await store.get("settings", SETTINGS_ID);
    expect(settings?.body.revokedDevices).toEqual([earlier, gone.id]);
    // a local write: the sync engine seals it under the keyring's current version, 2
    const outbox = await store.readOutbox(100);
    expect(outbox.find((e) => e.id === SETTINGS_ID)?.touched).toContain("revokedDevices");
    expect(await store.getMeta("keyV")).toBe(2);
    store.close();
  });

  it("the rotation posts a link that opens to the old data key under the new one", async () => {
    const a = await account();
    await (
      await rotateKeys({ ...a.options, remove: [], recovery: { text: a.recoveryKey } })
    ).commit();
    const link = a.api.rotations[0]?.link;
    expect(typeof link).toBe("string");
    const newDk = await openRecovery(a.api, a.userId, a.recoveryKey, 2);
    const opened = await openKeyLink(
      newDk,
      { userId: a.userId, keyV: 2 },
      fromBase64Url(link as string),
    );
    expect(opened).toEqual(a.dk);
  });

  it("a retried commit after a lost answer posts the same link, and landed() still holds", async () => {
    const a = await account();
    const prepared = await rotateKeys({
      ...a.options,
      remove: [],
      recovery: { text: a.recoveryKey },
    });
    a.api.loseNextAnswer = true;
    await prepared.commit().catch(() => undefined);
    expect(a.api.rotations[0]?.link).toBeTruthy();
    a.api.offline = false;
    await expect(prepared.commit()).resolves.toMatchObject({ keyV: 2 });
    expect(a.api.rotations).toHaveLength(1);
    // the retry was posted (and refused as a second rotation) with the very same link
    expect(a.api.posts).toHaveLength(2);
    expect(a.api.posts[1]?.link).toBe(a.api.posts[0]?.link);
    expect((await loadLocalKeys(a.userId))?.keyring.current).toBe(2);
  });

  it("a browser at v1 while the account is at v2 (valid link) refreshes first, rotates to v3 and holds 1, 2 and 3", async () => {
    const a = await account();
    // another device rotated to v2: the same recovery key, this browser's wrap sealed to DK(2)
    const dk2 = generateDataKey();
    const secret = parseRecoveryKey(a.recoveryKey);
    for (const wrap of a.api.wraps) {
      wrap.keyV = 2;
      if (wrap.kind === "recovery") {
        wrap.wrapped = toBase64Url(
          await wrapDataKey(secret, { kind: "recovery", userId: a.userId, keyV: 2 }, dk2),
        );
      }
    }
    wrapOf(a, a.own.id).wrapped = toBase64Url(
      await sealToDevice(
        fromBase64Url(a.own.publicKey as string),
        { kind: "device", userId: a.userId, keyV: 2 },
        dk2,
      ),
    );
    a.api.links.set(2, toBase64Url(await sealKeyLink(dk2, a.dk, { userId: a.userId, keyV: 2 })));
    const result = await (
      await rotateKeys({ ...a.options, remove: [], recovery: { text: a.recoveryKey } })
    ).commit();
    expect(result.keyV).toBe(3);
    const local = await loadLocalKeys(a.userId);
    expect(local?.keyring.current).toBe(3);
    expect([...(local?.keyring.byVersion.keys() ?? [])]).toEqual([1, 2, 3]);
    const ctx = { userId: a.userId, type: "settings" as const, id: SETTINGS_ID, keyV: 2 };
    const sealed = await sealRecord(await deriveRecordKeys(dk2, false), ctx, { s: 2 });
    expect(await openRecord(local?.keyring.byVersion.get(2) as never, ctx, sealed)).toEqual({
      s: 2,
    });
    // the link posted with v3 opens to DK(2)
    const dk3 = await openRecovery(a.api, a.userId, a.recoveryKey, 3);
    const link = a.api.rotations[0]?.link as string;
    expect(await openKeyLink(dk3, { userId: a.userId, keyV: 3 }, fromBase64Url(link))).toEqual(dk2);
  });

  it("a commit never overwrites a record key this browser already holds for the new version", async () => {
    const a = await account();
    const prepared = await rotateKeys({
      ...a.options,
      remove: [],
      recovery: { text: a.recoveryKey },
    });
    // record:2 appeared meanwhile (it must never be replaced: versions only grow)
    const held = await deriveRecordKeys(generateDataKey(), false);
    const store = await createEncryptedStore(a.userId);
    await store.putKey("record:2", held.record);
    await store.putKey("dedupe:2", held.dedupe);
    store.close();
    await expect(prepared.commit()).rejects.toEqual(new KeysError("tampered"));
    const after = await createEncryptedStore(a.userId);
    const kept = (await after.getKey<CryptoKey>("record:2")) as CryptoKey;
    const ctx = { userId: a.userId, type: "settings" as const, id: SETTINGS_ID, keyV: 2 };
    const sealed = await sealRecord(held, ctx, { s: 2 });
    expect(await openRecord({ record: kept, dedupe: held.dedupe }, ctx, sealed)).toEqual({ s: 2 });
    expect(await after.getMeta("keyV")).toBe(1);
    after.close();
  });

  it("a 2a vault at v1 rotates to v2, and a record sealed under v2 opens after a reload", async () => {
    const a = await account();
    const store = await createEncryptedStore(a.userId);
    const record = await store.getKey<CryptoKey>("record:1");
    const dedupe = await store.getKey<CryptoKey>("dedupe:1");
    await store.putKey("record", record);
    await store.putKey("dedupe", dedupe);
    await store.deleteKey("record:1");
    await store.deleteKey("dedupe:1");
    store.close();
    await (
      await rotateKeys({ ...a.options, remove: [], recovery: { text: a.recoveryKey } })
    ).commit();
    const local = await loadLocalKeys(a.userId);
    expect([...(local?.keyring.byVersion.keys() ?? [])]).toEqual([1, 2]);
    const newDk = await openRecovery(a.api, a.userId, a.recoveryKey, 2);
    const ctx = { userId: a.userId, type: "settings" as const, id: SETTINGS_ID, keyV: 2 };
    const sealed = await sealRecord(await deriveRecordKeys(newDk, false), ctx, { s: 2 });
    expect(await openRecord(local?.keyring.byVersion.get(2) as never, ctx, sealed)).toEqual({
      s: 2,
    });
    const ctx1 = { ...ctx, keyV: 1 };
    const sealed1 = await sealRecord(await deriveRecordKeys(a.dk, false), ctx1, { s: 1 });
    expect(await openRecord(local?.keyring.byVersion.get(1) as never, ctx1, sealed1)).toEqual({
      s: 1,
    });
  });

  it("a 409 key_version_mismatch from rotate is rotated_elsewhere and leaves the local keys untouched", async () => {
    const a = await account();
    const gone = await addDevice(a, "Chrome on Android");
    const prepared = await rotateKeys({
      ...a.options,
      remove: [gone.id],
      recovery: { text: a.recoveryKey },
    });
    a.api.rotatedElsewhere = true;
    const err = await prepared.commit().catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("rotated_elsewhere");
    const local = await loadLocalKeys(a.userId);
    expect(local?.keyring.current).toBe(1);
    expect([...(local?.keyring.byVersion.keys() ?? [])]).toEqual([1]);
    const store = await createEncryptedStore(a.userId);
    expect((await store.get("settings", SETTINGS_ID))?.body.revokedDevices).toEqual([]);
    expect(await store.getKey("record:2")).toBeUndefined();
    store.close();
  });

  it("a rotation whose answer was lost is recognised as ours on retry, and kept locally", async () => {
    const a = await account();
    const gone = await addDevice(a, "Chrome on Android");
    const prepared = await rotateKeys({
      ...a.options,
      remove: [gone.id],
      recovery: { fresh: true },
    });
    a.api.loseNextAnswer = true;
    const err = await prepared.commit().catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("offline");
    expect(a.api.rotations).toHaveLength(1); // the server did commit
    expect((await loadLocalKeys(a.userId))?.keyring.current).toBe(1);

    a.api.offline = false;
    const result = await prepared.commit();
    expect(result).toEqual({
      keyV: 2,
      dropped: [{ id: gone.id, label: "Chrome on Android", reason: "removed" }],
    });
    expect(a.api.rotations).toHaveLength(1);
    expect((await loadLocalKeys(a.userId))?.keyring.current).toBe(2);
    const store = await createEncryptedStore(a.userId);
    expect((await store.get("settings", SETTINGS_ID))?.body.revokedDevices).toEqual([gone.id]);
    store.close();
    // the shown key is the account's recovery key
    await expect(
      openRecovery(a.api, a.userId, prepared.recoveryKey as string, 2),
    ).resolves.toHaveLength(32);
  });

  it("a 409 after another device's rotation (its wraps, not ours) is rotated_elsewhere, local keys untouched", async () => {
    const a = await account();
    const prepared = await rotateKeys({
      ...a.options,
      remove: [],
      recovery: { text: a.recoveryKey },
    });
    // another device rotated to keyV 2: its own DK, sealed to this browser's public key too
    const theirs = generateDataKey();
    for (const wrap of a.api.wraps) wrap.keyV = 2;
    const own = wrapOf(a, a.own.id);
    own.wrapped = toBase64Url(
      await sealToDevice(
        fromBase64Url(a.own.publicKey as string),
        { kind: "device", userId: a.userId, keyV: 2 },
        theirs,
      ),
    );

    const err = await prepared.commit().catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("rotated_elsewhere");
    expect(a.api.rotations).toEqual([]);
    const local = await loadLocalKeys(a.userId);
    expect(local?.keyring.current).toBe(1);
    expect([...(local?.keyring.byVersion.keys() ?? [])]).toEqual([1]);
    const store = await createEncryptedStore(a.userId);
    expect(await store.getKey("record:2")).toBeUndefined();
    store.close();
  });

  it("DK, the new DK and the recovery secret are zeroed after commit or failure", async () => {
    const zeroed = (list: Uint8Array[]) => list.every((b) => b.every((x) => x === 0));
    const a = await account();
    await (
      await rotateKeys({ ...a.options, remove: [], recovery: { text: a.recoveryKey } })
    ).commit();
    expect(handed.dataKeys).toHaveLength(1);
    expect(handed.opened.length).toBeGreaterThan(0);
    expect(handed.unwrapped.length).toBeGreaterThan(0);
    expect(handed.parsed).toHaveLength(1);
    for (const list of Object.values(handed)) expect(zeroed(list)).toBe(true);

    clearHanded();
    const b = await account();
    const fresh = await rotateKeys({ ...b.options, remove: [], recovery: { fresh: true } });
    b.api.rotatedElsewhere = true;
    await fresh.commit().catch(() => {});
    expect(handed.secrets).toHaveLength(1);
    expect(handed.dataKeys).toHaveLength(1);
    for (const list of Object.values(handed)) expect(zeroed(list)).toBe(true);

    clearHanded();
    const stranger = formatRecoveryKey(crypto.getRandomValues(new Uint8Array(16)));
    await rotateKeys({ ...b.options, remove: [], recovery: { text: stranger } }).catch(() => {});
    expect(handed.parsed).toHaveLength(1);
    for (const list of Object.values(handed)) expect(zeroed(list)).toBe(true);
  });
});

describe("a device wrap that holds another data key at a held key version", () => {
  /** The server seals another DK to this browser's public key, at the version it already holds. */
  async function forgeOwnWrap(a: Account) {
    const forged = generateDataKey();
    a.own.wrapped = toBase64Url(
      await sealToDevice(
        fromBase64Url(a.own.publicKey as string),
        { kind: "device", userId: a.userId, keyV: 1 },
        forged,
      ),
    );
    clearHanded();
    return forged;
  }
  const zeroed = (list: Uint8Array[]) => list.every((b) => b.every((x) => x === 0));

  it("rotateKeys refuses it as tampered: nothing is made or sent, and the opened DK is zeroed", async () => {
    const a = await account();
    await addDevice(a, "Phone");
    await forgeOwnWrap(a);
    const err = await rotateKeys({
      ...a.options,
      remove: [],
      recovery: { text: a.recoveryKey },
    }).catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("tampered");
    expect(a.api.rotations).toEqual([]);
    expect(a.api.puts).toEqual([]);
    expect(handed.dataKeys).toEqual([]);
    expect(handed.opened.length).toBeGreaterThan(0);
    expect(zeroed(handed.opened)).toBe(true);
    expect((await loadLocalKeys(a.userId))?.keyring.current).toBe(1);
  });

  it("newRecoveryKey refuses it as tampered, and sends nothing", async () => {
    const a = await account();
    await forgeOwnWrap(a);
    await expect(newRecoveryKey(a.options)).rejects.toMatchObject({ code: "tampered" });
    expect(a.api.puts).toEqual([]);
    expect(zeroed(handed.opened)).toBe(true);
  });
});

describe("newRecoveryKey", () => {
  it("newRecoveryKey replaces the recovery wrap at the current keyV (PUT, same kind) only on commit", async () => {
    const a = await account();
    const prepared = await newRecoveryKey(a.options);
    expect(prepared.recoveryKey).toMatch(/^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$/);
    expect(a.api.puts).toEqual([]);
    // the old key still opens until commit
    await expect(openRecovery(a.api, a.userId, a.recoveryKey, 1)).resolves.toEqual(a.dk);

    await prepared.commit();
    expect(a.api.puts.map((p) => [p.kind, p.keyV])).toEqual([["recovery", 1]]);
    expect(a.api.wraps.filter((w) => w.kind === "recovery")).toHaveLength(1);
    await expect(openRecovery(a.api, a.userId, prepared.recoveryKey, 1)).resolves.toEqual(a.dk);
    await expect(openRecovery(a.api, a.userId, a.recoveryKey, 1)).rejects.toThrow();
    expect(a.api.rotations).toEqual([]);
    expect(handed.secrets.every((s) => s.every((x) => x === 0))).toBe(true);
  });
});

describe("newRecoveryKey commit", () => {
  it("a PUT whose answer was lost counts as saved when GET /v2/keys shows the prepared wrap", async () => {
    const a = await account();
    const prepared = await newRecoveryKey(a.options);
    a.api.losePutAnswer = true;
    await expect(prepared.commit()).resolves.toBeUndefined();
    await expect(openRecovery(a.api, a.userId, prepared.recoveryKey, 1)).resolves.toEqual(a.dk);
  });

  it("a failed commit is retried with the same wrap id; offline throughout is offline", async () => {
    const a = await account();
    const prepared = await newRecoveryKey(a.options);
    a.api.offline = true;
    await expect(prepared.commit()).rejects.toMatchObject({ code: "offline" });
    a.api.offline = false;
    await prepared.commit();
    const [put] = a.api.puts;
    expect(a.api.puts).toHaveLength(1);
    expect(a.api.wraps.find((w) => w.kind === "recovery")?.id).toBe(put?.id);
  });

  it("a key version that moved is rotated_elsewhere, and nothing was kept", async () => {
    const a = await account();
    const prepared = await newRecoveryKey(a.options);
    for (const w of a.api.wraps) w.keyV = 2;
    await expect(prepared.commit()).rejects.toMatchObject({ code: "rotated_elsewhere" });
    expect(a.api.puts).toEqual([]);
  });
});

describe("checkRecoveryKey", () => {
  it("resolves for the account's recovery key, and names a wrong or malformed one; the secret is zeroed", async () => {
    const a = await account();
    await expect(checkRecoveryKey({ ...a.options, text: a.recoveryKey })).resolves.toBeUndefined();
    const stranger = formatRecoveryKey(crypto.getRandomValues(new Uint8Array(16)));
    await expect(checkRecoveryKey({ ...a.options, text: stranger })).rejects.toMatchObject({
      code: "wrong_recovery_key",
    });
    await expect(checkRecoveryKey({ ...a.options, text: "nope" })).rejects.toMatchObject({
      code: "bad_recovery_key",
    });
    expect(handed.parsed).toHaveLength(2);
    expect(handed.parsed.every((s) => s.every((x) => x === 0))).toBe(true);
    expect(handed.opened).toEqual([]);
    expect(a.api.puts).toEqual([]);
  });
});
