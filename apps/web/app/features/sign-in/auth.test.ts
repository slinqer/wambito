import { afterEach, describe, expect, it, vi } from "vitest";
import { KeysError } from "../../local/keys.ts";
import { clearSignInPrf, takeSignInPrf } from "../../local/prf.ts";
import { SigninError, type WebSignin } from "../../local/signin.ts";
import { passkeyGaveNoPrf } from "../../local/unlock-hint.ts";
import {
  authErrorKey,
  createSessionSafeAuth,
  destinationAfterSignIn,
  keepPrfOf,
  langFrom,
  offersPasskey,
  passkeyErrorKey,
  retryAfterSeconds,
  signInLocale,
  verifyErrorKey,
} from "./auth.ts";

describe("authErrorKey", () => {
  it.each([
    [{ code: "INVALID_OTP", status: 400 }, "errors.invalid_code"],
    [{ code: "OTP_EXPIRED", status: 400 }, "errors.invalid_or_expired_code"],
    [{ code: "TOO_MANY_ATTEMPTS", status: 403 }, "errors.too_many_attempts"],
    [{ code: "INVALID_EMAIL", status: 400 }, "errors.invalid_email"],
    [{ code: "sign_in_not_allowed", status: 403 }, "errors.sign_in_not_allowed"],
    [{ code: "account_suspended", status: 403 }, "errors.account_suspended"],
    [{ status: 0 }, "errors.network_error"],
    [{ status: 502 }, "errors.internal_error"],
    [{ code: "SOMETHING_NEW", status: 400 }, "errors.generic"],
  ])("maps %j to %s", (error, key) => {
    expect(authErrorKey(error, "send")).toBe(key);
    expect(authErrorKey(error, "sign_in")).toBe(key);
  });

  it("tells a code-request limit (minutes) from a sign-in limit (seconds)", () => {
    expect(authErrorKey({ status: 429 }, "send")).toBe("errors.too_many_requests");
    expect(authErrorKey({ code: "TOO_MANY_REQUESTS", status: 429 }, "send")).toBe(
      "errors.too_many_requests",
    );
    expect(authErrorKey({ status: 429 }, "sign_in")).toBe("errors.too_many_sign_in_attempts");
  });
});

describe("verifyErrorKey", () => {
  it("reads every code problem on the magic link as invalid or expired", () => {
    for (const code of ["INVALID_OTP", "OTP_EXPIRED", "TOO_MANY_ATTEMPTS", "INVALID_EMAIL"]) {
      expect(verifyErrorKey({ code, status: 400 })).toBe("errors.invalid_or_expired_code");
    }
  });

  it("keeps what a retry of the same link can fix: connection, server, sign-in rate limit", () => {
    expect(verifyErrorKey({ status: 0 })).toBe("errors.network_error");
    expect(verifyErrorKey({ status: 503 })).toBe("errors.internal_error");
    expect(verifyErrorKey({ status: 429 })).toBe("errors.too_many_sign_in_attempts");
  });

  it("says a suspended account is suspended, not that the link expired", () => {
    expect(verifyErrorKey({ code: "account_suspended", status: 403 })).toBe(
      "errors.account_suspended",
    );
  });
});

describe("passkeyErrorKey", () => {
  it("says nothing when the person closed the browser's prompt", () => {
    expect(passkeyErrorKey({ code: "AUTH_CANCELLED", status: 400 })).toBeNull();
    expect(passkeyErrorKey({ code: "ERROR_CEREMONY_ABORTED", status: 400 })).toBeNull();
  });

  it("explains a passkey that did not work, and keeps transient problems", () => {
    expect(passkeyErrorKey({ code: "PASSKEY_NOT_FOUND", status: 400 })).toBe(
      "errors.passkey_failed",
    );
    expect(passkeyErrorKey({ status: 0 })).toBe("errors.network_error");
  });

  it("says a suspended account is suspended, not that the passkey failed", () => {
    expect(passkeyErrorKey({ code: "account_suspended", status: 403 })).toBe(
      "errors.account_suspended",
    );
  });
});

describe("retryAfterSeconds", () => {
  it("reads Better Auth's X-Retry-After, or a standard Retry-After in seconds", () => {
    expect(retryAfterSeconds(new Headers({ "X-Retry-After": "7" }))).toBe(7);
    expect(retryAfterSeconds(new Headers({ "Retry-After": "2.2" }))).toBe(3);
    expect(retryAfterSeconds(new Headers({ "Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT" }))).toBe(
      undefined,
    );
    expect(retryAfterSeconds(new Headers())).toBeUndefined();
  });
});

describe("destinationAfterSignIn", () => {
  it("sends someone who has not finished onboarding to /welcome", () => {
    expect(destinationAfterSignIn({ onboardingCompletedAt: null }, "/app/insights")).toBe(
      "/welcome",
    );
    expect(destinationAfterSignIn({}, null)).toBe("/welcome");
  });

  it("sends anyone to an assistant's consent first, onboarded or not", () => {
    const consent = "/oauth/consent?client_id=abc&sig=xyz";
    expect(destinationAfterSignIn({ onboardingCompletedAt: null }, consent)).toBe(consent);
  });

  it("sends an onboarded user to a same-origin next, or to /app", () => {
    const user = { onboardingCompletedAt: "2026-10-01T10:00:00.000Z" };
    expect(destinationAfterSignIn(user, "/app/insights")).toBe("/app/insights");
    expect(destinationAfterSignIn(user, null)).toBe("/app");
    expect(destinationAfterSignIn(user, "https://evil.example")).toBe("/app");
    expect(destinationAfterSignIn(user, "/.//evil.example")).toBe("/app");
  });
});

describe("langFrom", () => {
  it("accepts only the languages the app speaks", () => {
    expect(langFrom("en")).toBe("en");
    expect(langFrom("es")).toBe("es");
    expect(langFrom("it")).toBe("it");
    expect(langFrom("pt")).toBe("pt");
    expect(langFrom("fr")).toBeNull();
    expect(langFrom("EN")).toBeNull();
    expect(langFrom(null)).toBeNull();
  });
});

describe("signInLocale", () => {
  it("takes the landing's ?lang first, else the browser's language", () => {
    expect(signInLocale("es", "en-US")).toBe("es");
    expect(signInLocale("en", "es-CO")).toBe("en");
    expect(signInLocale(null, "es-CO")).toBe("es");
    expect(signInLocale(null, "en-GB")).toBe("en");
    expect(signInLocale("fr", "es-ES")).toBe("es");
  });
});

describe("offersPasskey", () => {
  it("a qr or recovery sign-in never offers a passkey", () => {
    expect(offersPasskey("qr", "/app")).toBe(false);
    expect(offersPasskey("recovery", "/app")).toBe(false);
    expect(offersPasskey("passkey", "/app")).toBe(false);
    expect(offersPasskey("email", "/app")).toBe(true);
    expect(offersPasskey("email", "/oauth/consent?client_id=abc")).toBe(false);
  });
});

describe("createSessionSafeAuth", () => {
  it("a recovery sign-in whose unlock fails after the 200 signs out; one refused before it does not", async () => {
    const signOut = vi.fn(async () => {});
    const auth = createSessionSafeAuth({
      signOut,
      startSignin: vi.fn() as never,
      signInWithRecoveryKey: async (text, deps) => {
        const response = await (deps?.fetch ?? fetch)("/api/v2/recovery/sign-in", {
          method: "POST",
        });
        if (!response.ok) throw new KeysError("recovery_key_invalid", 401);
        throw new KeysError(text === "unlock fails" ? "wrong_recovery_key" : "server");
      },
      fetch: async () => new Response(null, { status: 200 }),
    });
    expect(await auth.signInWithRecoveryKey("unlock fails")).toEqual({
      error: "wrong_recovery_key",
    });
    expect(signOut).toHaveBeenCalledTimes(1);
    const refused = createSessionSafeAuth({
      signOut,
      startSignin: vi.fn() as never,
      signInWithRecoveryKey: async (_text, deps) => {
        const response = await (deps?.fetch ?? fetch)("/api/v2/recovery/sign-in", {
          method: "POST",
        });
        if (!response.ok) throw new KeysError("recovery_key_invalid", 401);
        return { userId: "u-1", keys: {} as never };
      },
      fetch: async () => new Response(null, { status: 401 }),
    });
    expect(await refused.signInWithRecoveryKey("x")).toEqual({ error: "recovery_key_invalid" });
    expect(signOut).toHaveBeenCalledTimes(1);
  });

  it("a refused recovery sign-in reads its code and retry-after, and leaves no sign-out", async () => {
    const signOut = vi.fn(async () => {});
    const auth = createSessionSafeAuth({
      signOut,
      startSignin: vi.fn() as never,
      signInWithRecoveryKey: async () => {
        throw new KeysError("too_many_requests", 429, 30);
      },
      fetch: async () => new Response(null, { status: 429 }),
    });
    expect(await auth.signInWithRecoveryKey("x")).toEqual({
      error: "too_many_requests",
      retryAfterS: 30,
    });
    await expect(
      createSessionSafeAuth({
        signOut,
        startSignin: vi.fn() as never,
        signInWithRecoveryKey: async () => ({ userId: "u-1", keys: {} as never }),
        fetch: async () => new Response(null, { status: 200 }),
      }).signInWithRecoveryKey("good"),
    ).resolves.toEqual({ userId: "u-1" });
    expect(signOut).not.toHaveBeenCalled();
  });

  it("a qr sign-in whose finish fails after the pickup answered signs out; one that fails before does not", async () => {
    const signOut = vi.fn(async () => {});
    const fake = (pickupStatus: number) =>
      createSessionSafeAuth({
        signOut,
        signInWithRecoveryKey: vi.fn() as never,
        fetch: async () => new Response(null, { status: pickupStatus }),
        startSignin: async (options) =>
          ({
            id: "id",
            code: "ABCDEFGH",
            qr: "wambito://signin?id=id&key=k",
            expiresAt: "",
            number: async () => "123456",
            ready: async () => {},
            finish: async () => {
              const response = await (options.fetch ?? fetch)("/api/v2/signin/id/pickup", {
                method: "POST",
              });
              if (!response.ok) throw new SigninError("expired");
              throw new KeysError("server", 500);
            },
            cancel: () => {},
          }) satisfies WebSignin,
      });
    const after = await fake(200).startQrSignin({ remember: true, label: "Web" });
    await expect(after.finish()).rejects.toBeInstanceOf(KeysError);
    expect(signOut).toHaveBeenCalledTimes(1);
    const before = await fake(404).startQrSignin({ remember: true, label: "Web" });
    await expect(before.finish()).rejects.toBeInstanceOf(SigninError);
    expect(signOut).toHaveBeenCalledTimes(1);
  });
});

describe("keepPrfOf (a passkey sign-in's PRF and the unlock hint)", () => {
  const stubStorage = () => {
    const data = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      getItem: (key: string) => data.get(key) ?? null,
      setItem: (key: string, value: string) => void data.set(key, value),
      removeItem: (key: string) => void data.delete(key),
    });
  };
  const signedIn = (first?: Uint8Array) => ({
    data: { user: { id: "user-1" } },
    error: null,
    webauthn: {
      response: { id: "cred-1" },
      clientExtensionResults: first ? { prf: { results: { first } } } : { prf: {} },
    },
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    clearSignInPrf();
  });

  it("a passkey sign-in without PRF notes the hint for the user who signed in", () => {
    stubStorage();
    keepPrfOf(signedIn());
    expect(passkeyGaveNoPrf("user-1")).toBe(true);
    expect(passkeyGaveNoPrf("user-2")).toBe(false);
    expect(takeSignInPrf("user-1")).toBeNull();
  });

  it("with PRF it does not", () => {
    stubStorage();
    keepPrfOf(signedIn(new Uint8Array(32).fill(5)));
    expect(passkeyGaveNoPrf("user-1")).toBe(false);
    expect(takeSignInPrf("user-1")).not.toBeNull();
  });

  it("a failed sign-in notes nothing", () => {
    stubStorage();
    keepPrfOf({ ...signedIn(), data: null, error: { status: 400 } });
    expect(passkeyGaveNoPrf("user-1")).toBe(false);
  });
});
