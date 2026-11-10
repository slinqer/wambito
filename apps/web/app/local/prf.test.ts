import { PRF_SALT } from "@wambito/crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { KeysError } from "./keys.ts";
import {
  clearSignInPrf,
  evaluatePrf,
  keepSignInPrf,
  prfExtension,
  readPrf,
  takeSignInPrf,
} from "./prf.ts";

const bytes = (n: number, fill = 7) => new Uint8Array(n).fill(fill);

afterEach(() => {
  vi.unstubAllGlobals();
  clearSignInPrf();
});

describe("prfExtension", () => {
  it("asks for the PRF evaluated at PRF_SALT", () => {
    const ext = prfExtension();
    expect(ext.prf.eval.first).toEqual(PRF_SALT);
    // A copy: nothing that handles it can change the salt.
    expect(ext.prf.eval.first).not.toBe(PRF_SALT);
  });
});

describe("readPrf", () => {
  it("is null with no prf", () => {
    expect(readPrf({})).toBeNull();
    expect(readPrf(undefined)).toBeNull();
  });

  it("is null with prf: {} (the Proton Pass shape)", () => {
    expect(readPrf({ prf: {} })).toBeNull();
    expect(readPrf({ prf: { enabled: true } })).toBeNull();
  });

  it("is null with 16 bytes", () => {
    expect(readPrf({ prf: { results: { first: bytes(16).buffer } } })).toBeNull();
  });

  it("takes results.first as an ArrayBuffer of 32 bytes, copies the bytes and zeroes the source", () => {
    const source = bytes(32);
    const prf = readPrf({ prf: { results: { first: source.buffer } } });
    expect(prf).toEqual(bytes(32));
    // The browser's copy is zeroed: only the returned bytes hold the PRF.
    expect(source).toEqual(new Uint8Array(32));
  });
});

describe("evaluatePrf", () => {
  function stubCredentials(get: (options: CredentialRequestOptions) => Promise<unknown>) {
    const fetch = vi.fn();
    vi.stubGlobal("fetch", fetch);
    vi.stubGlobal("location", { hostname: "app.wambito.test" });
    vi.stubGlobal("navigator", { credentials: { get: vi.fn(get) } });
    return {
      fetch,
      get: (navigator as unknown as { credentials: { get: ReturnType<typeof vi.fn> } }).credentials
        .get,
    };
  }

  const credential = (id: string, results: unknown) => ({
    id,
    getClientExtensionResults: () => results,
  });

  it("a passkey without PRF results is no_prf, and nothing is sent", async () => {
    const { fetch } = stubCredentials(async () => credential("cred-1", { prf: {} }));
    await expect(evaluatePrf()).rejects.toEqual(new KeysError("no_prf"));
    expect(fetch).not.toHaveBeenCalled();
  });

  it("asks the browser for this site, the given credentials, with user verification", async () => {
    const { get, fetch } = stubCredentials(async () =>
      credential("AQID", { prf: { results: { first: bytes(32).buffer } } }),
    );
    const result = await evaluatePrf(["AQID"]);
    expect(result).toEqual({ credentialId: "AQID", prf: bytes(32) });
    const options = get.mock.calls[0]?.[0] as CredentialRequestOptions;
    const publicKey = options.publicKey as PublicKeyCredentialRequestOptions;
    expect(publicKey.rpId).toBe("app.wambito.test");
    expect(publicKey.userVerification).toBe("required");
    expect((publicKey.challenge as Uint8Array).byteLength).toBe(32);
    expect(publicKey.allowCredentials).toEqual([
      { type: "public-key", id: new Uint8Array([1, 2, 3]) },
    ]);
    expect(publicKey.extensions).toEqual(prfExtension());
    expect(fetch).not.toHaveBeenCalled();
  });

  it("is null when the person cancels", async () => {
    stubCredentials(async () => {
      throw new DOMException("cancelled", "NotAllowedError");
    });
    await expect(evaluatePrf()).resolves.toBeNull();
  });
});

describe("the sign-in stash", () => {
  const A = "user_a";
  const B = "user_b";

  it("is read once, by its account", () => {
    keepSignInPrf({ userId: A, credentialId: "c", prf: bytes(32) });
    expect(takeSignInPrf(A)).toEqual({ credentialId: "c", prf: bytes(32) });
    expect(takeSignInPrf(A)).toBeNull();
  });

  it("a stash from user A is not used by user B, and is zeroed", () => {
    const prf = bytes(32);
    keepSignInPrf({ userId: A, credentialId: "c", prf });
    expect(takeSignInPrf(B)).toBeNull();
    expect(prf).toEqual(new Uint8Array(32));
    expect(takeSignInPrf(A)).toBeNull();
  });

  it("clearing it zeroes the kept PRF", () => {
    const prf = bytes(32);
    keepSignInPrf({ userId: A, credentialId: "c", prf });
    clearSignInPrf();
    expect(prf).toEqual(new Uint8Array(32));
    expect(takeSignInPrf(A)).toBeNull();
  });

  it("a new one zeroes the one it replaces", () => {
    const old = bytes(32);
    keepSignInPrf({ userId: A, credentialId: "a", prf: old });
    keepSignInPrf({ userId: A, credentialId: "b", prf: bytes(32, 9) });
    expect(old).toEqual(new Uint8Array(32));
    expect(takeSignInPrf(A)?.credentialId).toBe("b");
  });
});
