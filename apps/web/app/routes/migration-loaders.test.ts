import { beforeEach, describe, expect, it, vi } from "vitest";

const auth = vi.hoisted(() => ({
  gate: { vault: null, migration: null } as {
    vault: unknown;
    migration: unknown;
  },
  onboarded: vi.fn(async () => {}),
  user: { isAnonymous: false, onboardingCompletedAt: null as string | null },
}));

vi.mock("../auth/encryption.ts", () => ({
  accountGate: vi.fn(async () => auth.gate),
  previewProfile: vi.fn(async () => auth.gate.vault),
}));
vi.mock("../auth/session.ts", () => ({
  requireSession: vi.fn(async () => auth.user),
  requireOnboarded: auth.onboarded,
}));
vi.mock("../auth/seen.ts", () => ({ markSeenToday: vi.fn(async () => {}) }));

const app = await import("./app.tsx");
const welcome = await import("./welcome.tsx");
const consent = await import("./oauth.consent.tsx");

const PROFILE = {
  id: "u-1",
  email: "ana@wambito.test",
  isAnonymous: false,
  locale: "es",
  timezone: "Europe/Madrid",
};

/** The loaders read only the request. */
const args = (url: string): any => ({ request: new Request(`http://app${url}`) });

beforeEach(() => {
  auth.gate = { vault: null, migration: null };
  auth.onboarded.mockClear();
  auth.user = { isAnonymous: false, onboardingCompletedAt: null };
});

describe("loaders of an account whose move is open or running", () => {
  it("/app runs the flow before the plain app or the vault gate", async () => {
    auth.gate = { vault: null, migration: { profile: PROFILE, migration: "available" } };
    await expect(app.clientLoader(args("/app"))).resolves.toEqual({
      vault: null,
      migration: { profile: PROFILE, migration: "available" },
    });
    // The flow comes first: onboarding is the vault's to decide afterwards.
    expect(auth.onboarded).not.toHaveBeenCalled();
  });

  it("/app of a plain account keeps the plain app", async () => {
    await expect(app.clientLoader(args("/app"))).resolves.toEqual({
      vault: null,
      migration: null,
    });
    expect(auth.onboarded).toHaveBeenCalledTimes(1);
  });

  it("/welcome runs the flow too, even for an onboarded account", async () => {
    auth.user = { isAnonymous: false, onboardingCompletedAt: "2026-09-01T08:00:00.000Z" };
    auth.gate = { vault: null, migration: { profile: PROFILE, migration: "in_progress" } };
    await expect(welcome.clientLoader(args("/welcome"))).resolves.toEqual({
      vault: null,
      migration: { profile: PROFILE, migration: "in_progress" },
    });
  });

  it("the consent page sends a running move to the flow", async () => {
    auth.gate = { vault: null, migration: { profile: PROFILE, migration: "in_progress" } };
    const thrown = await consent
      .clientLoader(args("/oauth/consent?client_id=c&sig=s"))
      .catch((e: unknown) => e);
    expect(thrown).toBeInstanceOf(Response);
    expect((thrown as Response).headers.get("location")).toBe("/app");
  });

  it("the consent page of an account the move is only open to stays plain", async () => {
    auth.gate = { vault: null, migration: { profile: PROFILE, migration: "available" } };
    await expect(consent.clientLoader(args("/oauth/consent?client_id=c&sig=s"))).resolves.toEqual({
      guest: false,
      encrypted: null,
    });
  });
});
