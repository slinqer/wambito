import { afterEach, describe, expect, it, vi } from "vitest";
import appEn from "../../i18n/messages/app.en.json" with { type: "json" };
import type { VaultSession } from "../../local/vault-session.ts";
import {
  changeKeys,
  codeOf,
  liveSecurity,
  type RotateRequest,
  type SecurityApi,
} from "./security.ts";

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

describe("removeDevice", () => {
  afterEach(() => vi.unstubAllGlobals());
  const ID = "0193a000-0000-7000-8000-00000000000b";
  const live = () => liveSecurity({ userId: "u-ana" } as VaultSession);
  const stubFetch = (impl: (url: string, init?: RequestInit) => Response | Promise<Response>) => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) =>
      impl(String(input), init),
    );
    vi.stubGlobal("fetch", fetchMock);
    return fetchMock;
  };

  it("sends DELETE /v2/keys/{id} and nothing to /v2/keys/rotate", async () => {
    const fetchMock = stubFetch(() => new Response(null, { status: 204 }));
    await expect(live().removeDevice(ID)).resolves.toBeUndefined();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(`/api/v2/keys/${ID}`);
    expect(init.method).toBe("DELETE");
    expect(fetchMock.mock.calls.some(([u]) => String(u).includes("/rotate"))).toBe(false);
  });

  it("a 404 resolves: it was already gone", async () => {
    stubFetch(() => new Response(JSON.stringify({ code: "not_found" }), { status: 404 }));
    await expect(live().removeDevice(ID)).resolves.toBeUndefined();
  });

  it("no connection rejects with offline", async () => {
    stubFetch(() => {
      throw new TypeError("network");
    });
    const error = await live()
      .removeDevice(ID)
      .catch((e: unknown) => e);
    expect(codeOf(error)).toBe("offline");
  });

  it("another failure rejects with failed", async () => {
    stubFetch(() => new Response(null, { status: 503 }));
    const error = await live()
      .removeDevice(ID)
      .catch((e: unknown) => e);
    expect(codeOf(error)).toBe("failed");
  });
});

describe("the rotation copy", () => {
  it("says that connected assistants are disconnected", () => {
    const security = appEn.settings.security;
    expect(security.change_keys_body).toContain("connected assistants are disconnected");
  });
});
