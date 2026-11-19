import { beforeEach, describe, expect, it, vi } from "vitest";

const order: string[] = [];
const forgetOwnDeviceWrap = vi.hoisted(() => vi.fn());
const signOut = vi.hoisted(() => vi.fn());

vi.mock("../../auth/auth-client.ts", () => ({ authClient: { signOut } }));
vi.mock("../../local/prf.ts", () => ({ clearSignInPrf: () => undefined }));
vi.mock("../../local/vault-session.ts", () => ({
  forgetOwnDeviceWrap,
  forgetVault: async () => undefined,
}));

import { liveSignOut } from "./use-sign-out.ts";

beforeEach(() => {
  order.length = 0;
  forgetOwnDeviceWrap.mockReset();
  signOut.mockReset();
  signOut.mockImplementation(async () => {
    order.push("signOut");
    return { error: null };
  });
});

describe("liveSignOut", () => {
  it("deletes the own device wrap before the session ends", async () => {
    forgetOwnDeviceWrap.mockImplementation(async () => {
      order.push("forgetOwnDeviceWrap");
    });
    await liveSignOut();
    expect(order).toEqual(["forgetOwnDeviceWrap", "signOut"]);
  });

  it("still signs out when the wrap delete fails", async () => {
    forgetOwnDeviceWrap.mockImplementation(async () => undefined);
    await expect(liveSignOut()).resolves.toEqual({ error: null });
    expect(signOut).toHaveBeenCalledOnce();
  });

  it("signs out promptly when the wrap delete is bounded by its timeout", async () => {
    // The real function resolves after its timeout; a slow one still lets the sign-out run.
    forgetOwnDeviceWrap.mockImplementation(
      () => new Promise<void>((resolve) => setTimeout(resolve, 50)),
    );
    const started = Date.now();
    await liveSignOut();
    expect(signOut).toHaveBeenCalledOnce();
    expect(Date.now() - started).toBeLessThan(1000);
  });
});
