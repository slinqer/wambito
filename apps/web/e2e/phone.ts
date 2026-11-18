import type { APIRequestContext } from "@playwright/test";
import { expect } from "@playwright/test";
import {
  fromBase64Url,
  generateDeviceKeyPair,
  pairingCommitment,
  parseRecoveryKey,
  sealToDevice,
  toBase64Url,
  unwrapDataKey,
} from "@wambito/crypto";

/**
 * The phone's half of a web sign-in (spec 2026-11-15 section 8, the API's `routes/signin.ts`),
 * played in Node over the API with the real crypto, so a web e2e needs no phone. `request` carries
 * the account's session (a signed-in browser context's `request`, through the web's `/api` proxy).
 */

interface Found {
  id: string;
  commitment: string;
  label: string;
  expiresAt: string;
}

interface Viewed extends Found {
  publicKey: string | null;
}

interface Wrap {
  kind: string;
  keyV: number;
  wrapped: string;
}

/**
 * Approves the sign-in the browser shows as `code`, as the phone does: `GET /v2/signin?code=` pins
 * the request's commitment; the data key comes from the recovery wrap (`GET /v2/keys`, opened with
 * the recovery key); an ephemeral `A` approves; once the browser has revealed its key (`GET
 * /v2/signin/{id}` polled), it is checked against the commitment and DK is sealed to it under
 * `{ kind: "device", userId, keyV }`.
 */
export async function approveSignin(options: {
  request: APIRequestContext;
  userId: string;
  code: string;
  recoveryKey: string;
}): Promise<void> {
  const { request, userId, code, recoveryKey } = options;
  const headers = { "x-wambito-user": userId };

  const foundRes = await request.get(`/api/v2/signin?code=${encodeURIComponent(code)}`, {
    headers,
  });
  expect(foundRes.status(), await foundRes.text()).toBe(200);
  const found = (await foundRes.json()) as Found;

  const keysRes = await request.get("/api/v2/keys", { headers });
  expect(keysRes.status(), await keysRes.text()).toBe(200);
  const { wraps } = (await keysRes.json()) as { wraps: Wrap[] };
  const recovery = wraps.find((w) => w.kind === "recovery");
  if (!recovery) throw new Error("The account has no recovery wrap");
  const keyV = recovery.keyV;
  const secret = parseRecoveryKey(recoveryKey);
  let dataKey: Uint8Array | undefined;
  try {
    dataKey = await unwrapDataKey(
      secret,
      { kind: "recovery", userId, keyV },
      fromBase64Url(recovery.wrapped),
    );

    const approver = await generateDeviceKeyPair();
    const approveRes = await request.post(`/api/v2/signin/${found.id}/approver`, {
      headers,
      data: { publicKey: toBase64Url(approver.publicKey) },
    });
    expect(approveRes.status(), await approveRes.text()).toBe(204);

    let revealed = "";
    await expect
      .poll(
        async () => {
          const res = await request.get(`/api/v2/signin/${found.id}`, { headers });
          expect(res.status(), await res.text()).toBe(200);
          revealed = ((await res.json()) as Viewed).publicKey ?? "";
          return revealed !== "";
        },
        { timeout: 20_000, message: "the browser reveals its key" },
      )
      .toBe(true);
    const browserKey = fromBase64Url(revealed);
    expect(toBase64Url(await pairingCommitment(browserKey)), "the commitment holds").toBe(
      found.commitment,
    );

    const sealed = await sealToDevice(
      browserKey,
      { kind: "device", userId, keyV },
      dataKey,
      approver,
    );
    const sealRes = await request.post(`/api/v2/signin/${found.id}/seal`, {
      headers,
      data: { sealed: toBase64Url(sealed), keyV },
    });
    expect(sealRes.status(), await sealRes.text()).toBe(204);
  } finally {
    secret.fill(0);
    dataKey?.fill(0);
  }
}
