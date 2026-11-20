import { beforeEach, describe, expect, it, vi } from "vitest";

const me = vi.hoisted(() => ({ data: {} as Record<string, unknown> }));
vi.mock("../api/client.ts", () => ({
  api: { GET: vi.fn(async () => ({ data: me.data, response: new Response(null) })) },
}));

const { accountGate, migrationOf, previewProfile } = await import("./encryption.ts");

const PROFILE = {
  id: "u-1",
  email: "ana@wambito.test",
  isAnonymous: false,
  locale: "es",
  timezone: "Europe/Madrid",
};

beforeEach(() => {
  me.data = { ...PROFILE, encryption: "plain" };
});

describe("migrationOf", () => {
  it("is the profile's move, or null", () => {
    expect(migrationOf({ migration: "available" })).toBe("available");
    expect(migrationOf({ migration: "in_progress" })).toBe("in_progress");
    expect(migrationOf({})).toBeNull();
  });
});

describe("accountGate", () => {
  it("a plain account: no vault, no move", async () => {
    await expect(accountGate()).resolves.toEqual({ vault: null, migration: null });
  });

  it("a plain account the move is open to runs the flow, not the plain app", async () => {
    me.data = { ...PROFILE, encryption: "plain", migration: "available" };
    await expect(accountGate()).resolves.toEqual({
      vault: null,
      migration: { profile: PROFILE, migration: "available" },
    });
  });

  it("a migrating account answers preview, but is the flow's, never the vault gate's", async () => {
    me.data = { ...PROFILE, encryption: "preview", migration: "in_progress" };
    const gate = await accountGate();
    expect(gate.vault).toBeNull();
    expect(gate.migration).toEqual({ profile: PROFILE, migration: "in_progress" });
    await expect(previewProfile()).resolves.toBeNull();
  });

  it("an encrypted account opens its vault", async () => {
    me.data = { ...PROFILE, encryption: "preview" };
    await expect(accountGate()).resolves.toEqual({ vault: PROFILE, migration: null });
    await expect(previewProfile()).resolves.toEqual(PROFILE);
  });

  it("tells onMe the id and time zone of any account", async () => {
    me.data = { ...PROFILE, encryption: "preview", migration: "in_progress" };
    const onMe = vi.fn();
    await accountGate(onMe);
    expect(onMe).toHaveBeenCalledWith({ id: "u-1", timezone: "Europe/Madrid" });
  });
});
