import { describe, expect, it, vi } from "vitest";
import appEn from "../../i18n/messages/app.en.json" with { type: "json" };
import { changeKeys, type RotateRequest, type SecurityApi } from "./security.ts";

const fakeSecurity = () => {
  const calls: string[] = [];
  const requests: RotateRequest[] = [];
  const result = { dropped: [] };
  const security = {
    rotate: vi.fn(async (request: RotateRequest) => {
      calls.push("rotate");
      requests.push(request);
      return {
        recoveryKey: null,
        commit: async () => {
          calls.push("commit");
          return result;
        },
      };
    }),
    reloadKeys: vi.fn(async () => {
      calls.push("reloadKeys");
    }),
  } as unknown as SecurityApi;
  return { security, calls, requests, result };
};

describe("Change keys", () => {
  it("rotates with the recovery key and removes nothing", async () => {
    const { security, calls, requests, result } = fakeSecurity();
    await expect(changeKeys(security, "ABCD-EFGH")).resolves.toBe(result);
    expect(requests).toEqual([{ remove: [], recovery: { text: "ABCD-EFGH" } }]);
    expect(calls).toEqual(["rotate", "commit", "reloadKeys"]);
  });

  it("keeps the rotation when the key reload fails (the sync retries on its own)", async () => {
    const { security } = fakeSecurity();
    vi.mocked(security.reloadKeys).mockRejectedValueOnce(new Error("offline"));
    await expect(changeKeys(security, "ABCD-EFGH")).resolves.toBeDefined();
  });

  it("a refused key does not commit", async () => {
    const { security, calls } = fakeSecurity();
    vi.mocked(security.rotate).mockRejectedValueOnce(
      Object.assign(new Error("x"), { code: "wrong_recovery_key" }),
    );
    await expect(changeKeys(security, "nope")).rejects.toMatchObject({
      code: "wrong_recovery_key",
    });
    expect(calls).toEqual([]);
  });
});

describe("the rotation copy", () => {
  it("says that connected assistants are disconnected", () => {
    const security = appEn.settings.security;
    expect(security.remove_sheet.body).toContain("Connected assistants are disconnected");
    expect(security.change_keys_body).toContain("connected assistants are disconnected");
  });
});
