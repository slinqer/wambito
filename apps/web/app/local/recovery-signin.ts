import { recoveryVerifier, toBase64Url } from "@wambito/crypto";
import { KeysError, type LocalKeys, parseRecoverySecret, unlockWithRecovery } from "./keys.ts";
import { deleteStaleVaults } from "./stale-vaults.ts";

/**
 * Signing in a signed-out browser with the recovery key (spec 2026-11-15; the API's
 * `routes/recovery.ts`). The typed text is parsed once, `recoveryVerifier(secret)` derives `lookup`
 * (16 bytes) and `auth` (32 bytes), and `POST /api/v2/recovery/sign-in` takes them base64url; the
 * 200 sets the session cookie and names the user. Then every other account's vault here is deleted
 * and `unlockWithRecovery` opens this browser with the same typed text (it also writes the
 * verifier, best effort). A failed unlock throws its own `KeysError`; the caller signs out.
 *
 * Signed out: plain `fetch` with `credentials: "same-origin"`, never `x-wambito-user`. The key
 * text, the secret, `lookup` and `auth` are never logged or stored; the secret and the derived
 * bytes are zeroed in a `finally`.
 *
 * `bad_recovery_key` (nothing sent) for text that does not parse; 401 `recovery_key_invalid`,
 * 403 `account_suspended`, 429 `too_many_requests` with `retryAfterS`, offline `offline`, the
 * rest `server`.
 */
export async function signInWithRecoveryKey(
  text: string,
  deps: { fetch?: typeof globalThis.fetch } = {},
): Promise<{ userId: string; keys: LocalKeys }> {
  const secret = parseRecoverySecret(text);
  let userId: string;
  try {
    const derived = await recoveryVerifier(secret);
    try {
      userId = await postSignIn(
        { lookup: toBase64Url(derived.lookup), auth: toBase64Url(derived.auth) },
        deps.fetch ?? globalThis.fetch,
      );
    } finally {
      derived.lookup.fill(0);
      derived.auth.fill(0);
    }
  } finally {
    secret.fill(0);
  }
  await deleteStaleVaults(userId);
  const keys = await unlockWithRecovery({ userId, text, fetch: deps.fetch });
  return { userId, keys };
}

async function postSignIn(
  body: { lookup: string; auth: string },
  fetchFn: typeof globalThis.fetch,
): Promise<string> {
  let response: Response;
  try {
    response = await fetchFn("/api/v2/recovery/sign-in", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    throw new KeysError("offline");
  }
  if (response.status === 401) throw new KeysError("recovery_key_invalid", 401);
  if (response.status === 403) throw new KeysError("account_suspended", 403);
  if (response.status === 429) {
    const value = Number(response.headers.get("retry-after"));
    throw new KeysError(
      "too_many_requests",
      429,
      Number.isInteger(value) && value >= 0 ? value : undefined,
    );
  }
  if (!response.ok) throw new KeysError("server", response.status);
  try {
    const { userId } = (await response.json()) as { userId?: unknown };
    if (typeof userId === "string" && userId !== "") return userId;
  } catch {
    // falls through
  }
  throw new KeysError("server", response.status);
}
