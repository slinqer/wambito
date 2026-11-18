import {
  formatRecoveryKey,
  fromBase64Url,
  newRecoverySecret,
  recoveryVerifier,
  toBase64Url,
} from "@wambito/crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";

/** What the crypto handed out, to check zeroing. */
const handed = vi.hoisted(() => ({
  verifiers: [] as Array<{ lookup: Uint8Array; auth: Uint8Array }>,
  secrets: [] as Uint8Array[],
}));
vi.mock("@wambito/crypto", async (original) => {
  const crypto = await original<typeof import("@wambito/crypto")>();
  return {
    ...crypto,
    parseRecoveryKey: (text: string) => {
      const secret = crypto.parseRecoveryKey(text);
      handed.secrets.push(secret);
      return secret;
    },
    recoveryVerifier: async (secret: Uint8Array) => {
      const out = await crypto.recoveryVerifier(secret);
      handed.verifiers.push(out);
      return out;
    },
  };
});

const calls = vi.hoisted(() => [] as string[]);
const unlock = vi.hoisted(() => vi.fn());
vi.mock("./keys.ts", async (original) => {
  const keys = await original<typeof import("./keys.ts")>();
  return {
    ...keys,
    unlockWithRecovery: async (options: { userId: string; text: string }) => {
      calls.push("unlock");
      return unlock(options);
    },
  };
});
vi.mock("./stale-vaults.ts", () => ({
  deleteStaleVaults: async (userId: string | null) => {
    calls.push(`stale:${userId}`);
  },
}));

import { KeysError } from "./keys.ts";
import { signInWithRecoveryKey } from "./recovery-signin.ts";

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });

const KEYS = { keyring: { current: 1, byVersion: new Map() } };

function fakeFetch(respond: () => Response) {
  const sent: Array<{ url: string; init?: RequestInit }> = [];
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    sent.push({ url: String(input), init });
    return respond();
  }) as typeof globalThis.fetch;
  return { fetch, sent };
}

beforeEach(() => {
  handed.verifiers.length = 0;
  handed.secrets.length = 0;
  calls.length = 0;
  unlock.mockReset();
  unlock.mockResolvedValue(KEYS);
});

describe("signInWithRecoveryKey", () => {
  it("posts lookup (16 bytes) and auth (32 bytes) derived from the key, then unlocks with the same text", async () => {
    const secret = newRecoverySecret();
    const text = formatRecoveryKey(secret);
    const expected = await recoveryVerifier(secret);
    const lookup = toBase64Url(expected.lookup);
    const auth = toBase64Url(expected.auth);
    const api = fakeFetch(() => json({ userId: "user_1" }));

    const out = await signInWithRecoveryKey(text, { fetch: api.fetch });

    expect(out).toEqual({ userId: "user_1", keys: KEYS });
    expect(api.sent).toHaveLength(1);
    const { url, init } = api.sent[0]!;
    expect(url).toBe("/api/v2/recovery/sign-in");
    expect(init?.method).toBe("POST");
    expect(init?.credentials).toBe("same-origin");
    expect(new Headers(init?.headers).has("x-wambito-user")).toBe(false);
    const body = JSON.parse(String(init?.body));
    expect(body).toEqual({ lookup, auth });
    expect(fromBase64Url(body.lookup).length).toBe(16);
    expect(fromBase64Url(body.auth).length).toBe(32);
    expect(calls).toEqual(["stale:user_1", "unlock"]);
    expect(unlock).toHaveBeenCalledWith(expect.objectContaining({ userId: "user_1", text }));
  });

  it('" abcd-efgh ijkl mnop qrst uvwx yz01 2345 " in lower case, with O for 0, signs in and unlocks', async () => {
    const secret = newRecoverySecret();
    const shown = formatRecoveryKey(secret);
    const messy = ` ${shown.toLowerCase().replaceAll("-", "  ").replaceAll("0", "o")} `;
    const expected = await recoveryVerifier(secret);
    const api = fakeFetch(() => json({ userId: "user_2" }));

    const out = await signInWithRecoveryKey(messy, { fetch: api.fetch });

    expect(out.userId).toBe("user_2");
    expect(JSON.parse(String(api.sent[0]?.init?.body))).toEqual({
      lookup: toBase64Url(expected.lookup),
      auth: toBase64Url(expected.auth),
    });
    expect(unlock).toHaveBeenCalledWith(expect.objectContaining({ text: messy }));
  });

  it("text that cannot be a key is bad_recovery_key and sends nothing", async () => {
    const api = fakeFetch(() => json({ userId: "x" }));
    const err = await signInWithRecoveryKey("not a key", { fetch: api.fetch }).catch((e) => e);
    expect(err).toBeInstanceOf(KeysError);
    expect(err.code).toBe("bad_recovery_key");
    expect(api.sent).toEqual([]);
    expect(calls).toEqual([]);
  });

  it("401 is recovery_key_invalid; 429 carries retryAfterS; 403 is account_suspended", async () => {
    const text = formatRecoveryKey(newRecoverySecret());
    const run = async (response: Response) => {
      const api = fakeFetch(() => response);
      return signInWithRecoveryKey(text, { fetch: api.fetch }).catch((e) => e);
    };
    const invalid = await run(json({ code: "recovery_key_invalid" }, 401));
    expect(invalid).toBeInstanceOf(KeysError);
    expect(invalid.code).toBe("recovery_key_invalid");
    const limited = await run(json({ code: "too_many_requests" }, 429, { "retry-after": "42" }));
    expect(limited.code).toBe("too_many_requests");
    expect(limited.retryAfterS).toBe(42);
    const suspended = await run(json({ code: "account_suspended" }, 403));
    expect(suspended.code).toBe("account_suspended");
    const broken = await run(json({ code: "x" }, 500));
    expect(broken.code).toBe("server");
    expect(calls).toEqual([]);
    expect(unlock).not.toHaveBeenCalled();
  });

  it("a network failure is offline", async () => {
    const fetch = (async () => {
      throw new TypeError("Failed to fetch");
    }) as typeof globalThis.fetch;
    const err = await signInWithRecoveryKey(formatRecoveryKey(newRecoverySecret()), {
      fetch,
    }).catch((e) => e);
    expect(err.code).toBe("offline");
  });

  it("an unlock that fails after a good sign-in throws its own error", async () => {
    unlock.mockRejectedValue(new KeysError("wrong_recovery_key"));
    const api = fakeFetch(() => json({ userId: "user_3" }));
    const err = await signInWithRecoveryKey(formatRecoveryKey(newRecoverySecret()), {
      fetch: api.fetch,
    }).catch((e) => e);
    expect(err.code).toBe("wrong_recovery_key");
  });

  it("the secret and the derived lookup and auth buffers are zeroed after the call", async () => {
    const api = fakeFetch(() => json({ userId: "user_4" }));
    await signInWithRecoveryKey(formatRecoveryKey(newRecoverySecret()), { fetch: api.fetch });
    expect(handed.verifiers).toHaveLength(1);
    const { lookup, auth } = handed.verifiers[0]!;
    expect(lookup.every((b) => b === 0)).toBe(true);
    expect(auth.every((b) => b === 0)).toBe(true);
    expect(handed.secrets.length).toBeGreaterThan(0);
    for (const s of handed.secrets) expect(s.every((b) => b === 0)).toBe(true);

    // also after a refusal
    handed.verifiers.length = 0;
    const refused = fakeFetch(() => json({ code: "recovery_key_invalid" }, 401));
    await signInWithRecoveryKey(formatRecoveryKey(newRecoverySecret()), {
      fetch: refused.fetch,
    }).catch(() => undefined);
    expect(handed.verifiers[0]?.lookup.every((b) => b === 0)).toBe(true);
    expect(handed.verifiers[0]?.auth.every((b) => b === 0)).toBe(true);
  });
});
