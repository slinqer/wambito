import type { MigrationCounts, MigrationRecord } from "@wambito/vault";
import { describe, expect, it, vi } from "vitest";
import {
  createMigrationFlow,
  type MigrationDeps,
  type MigrationState,
  type MigrationStep,
} from "./migration-flow.ts";

type Keys = { k: string };

const fail = (code: string) => Object.assign(new Error(code), { code });

/** Lets every pending promise settle. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

const RECORDS: MigrationRecord[] = [
  {
    type: "settings",
    id: "s-1",
    body: { s: 1, currency: "EUR", recoveryKeySavedAt: null },
    deleted: false,
  },
  { type: "category", id: "c-1", body: { s: 1, name: "Comida" }, deleted: false },
  { type: "transaction", id: "t-1", body: { s: 1, name: "Pan", amount: 250 }, deleted: false },
  { type: "transaction", id: "t-2", body: { s: 1, name: "Café", amount: 180 }, deleted: true },
];

const COUNTS: MigrationCounts = {
  transaction: 1,
  deletedTransaction: 1,
  category: 1,
  budget: 0,
  recurrence: 0,
  merchant: 0,
};

/**
 * What outlives a reload: the server's account (migrating or not) and this browser's vault (its
 * keys and the flow's meta). Every "page" is a new flow over the same world.
 */
function worldOf() {
  return {
    migrating: false,
    /** The move finished on the server: `GET /v1/me` has no `migration` and answers preview. */
    encrypted: false,
    keys: null as Keys | null,
    step: null as MigrationStep | null,
    keySavedAt: null as string | null,
    /** The records pushed to the server (the cancel deletes them). */
    pushed: 0,
    calls: [] as string[],
    prepared: 0,
  };
}

type World = ReturnType<typeof worldOf>;

function flowWith(world: World, overrides: Partial<MigrationDeps<Keys>> = {}) {
  const log = (name: string) => world.calls.push(name);
  const deps: MigrationDeps<Keys> = {
    migration: world.migrating ? "in_progress" : "available",
    loadLocalKeys: vi.fn(async () => {
      log("loadLocalKeys");
      return world.keys;
    }),
    prepareAccount: vi.fn(async () => {
      log("prepareAccount");
      world.prepared += 1;
      return {
        recoveryKey: "ABCD-EFGH-JKLM",
        commit: vi.fn(async () => {
          log("commit");
          world.keys = { k: `dk-${world.prepared}` };
          return world.keys;
        }),
      };
    }),
    unlockWithRecovery: vi.fn(async () => {
      log("unlockWithRecovery");
      world.keys = { k: "unlocked" };
      return world.keys;
    }),
    resume: vi.fn(async () => ({ step: world.step, keySavedAt: world.keySavedAt })),
    remember: vi.fn(async (step: MigrationStep | null, keySavedAt?: string | null) => {
      world.step = step;
      if (keySavedAt !== undefined) world.keySavedAt = keySavedAt;
    }),
    start: vi.fn(async () => {
      log("start");
      if (world.encrypted) throw fail("not_migratable");
      world.migrating = true;
    }),
    source: vi.fn(async () => {
      log("source");
      return RECORDS.map((r) => ({ ...r, body: { ...(r.body as object) } }));
    }),
    write: vi.fn(async () => {
      log("write");
    }),
    sync: vi.fn(async (_keys: Keys, onProgress: (done: number) => void) => {
      log("sync");
      world.pushed = RECORDS.length;
      onProgress(RECORDS.length);
    }),
    finish: vi.fn(async () => {
      log("finish");
      world.migrating = false;
      world.encrypted = true;
    }),
    cancel: vi.fn(async () => {
      log("cancel");
      if (!world.migrating) throw fail("not_migrating");
      world.migrating = false;
      world.pushed = 0;
    }),
    resetAll: vi.fn(async () => {
      log("resetAll");
    }),
    accountState: vi.fn(async () => {
      log("accountState");
      return world.encrypted ? ("encrypted" as const) : ("plain" as const);
    }),
    reload: vi.fn(() => {
      log("reload");
    }),
    now: () => new Date("2026-11-19T10:00:00Z"),
    ...overrides,
  };
  const flow = createMigrationFlow(deps);
  const seen: MigrationState["status"][] = [];
  flow.subscribe(() => seen.push(flow.getState().status));
  return { flow, deps, seen };
}

/** Runs a fresh account from the intro to the key screen. */
async function toKeys(world: World, overrides: Partial<MigrationDeps<Keys>> = {}) {
  const page = flowWith(world, overrides);
  page.flow.start();
  await settle();
  expect(page.flow.getState()).toEqual({ status: "intro" });
  await page.flow.begin();
  await settle();
  return page;
}

describe("migration flow", () => {
  it("runs start, keys, source, write, sync, finish in order", async () => {
    const world = worldOf();
    const { flow, deps, seen } = await toKeys(world);
    expect(flow.getState()).toEqual({
      status: "keys",
      recoveryKey: "ABCD-EFGH-JKLM",
      busy: false,
    });
    // Nothing is copied before the person confirms the key.
    expect(world.calls).not.toContain("commit");

    await flow.confirmKey();
    await settle();
    expect(world.calls).toEqual([
      "loadLocalKeys",
      "start",
      "prepareAccount",
      "commit",
      "resetAll",
      "source",
      "write",
      "sync",
      "finish",
    ]);
    expect(flow.getState()).toEqual({ status: "done" });
    expect(seen).toContain("copying");
    expect(seen).toContain("finishing");

    // The settings record says the recovery key was saved, the counts leave settings out.
    const written = (deps.write as ReturnType<typeof vi.fn>).mock.calls[0]?.[0] as
      | MigrationRecord[]
      | undefined;
    expect(written?.find((r) => r.type === "settings")?.body).toMatchObject({
      recoveryKeySavedAt: "2026-11-19T10:00:00.000Z",
    });
    expect(deps.finish).toHaveBeenCalledWith(COUNTS);
    expect(deps.sync).toHaveBeenCalledWith({ k: "dk-1" }, expect.any(Function));

    flow.continue();
    expect(world.calls.at(-1)).toBe("reload");
    expect(world.step).toBeNull();
  });

  it("shows the copy's progress", async () => {
    const world = worldOf();
    let progress: ((done: number) => void) | undefined;
    let release: (() => void) | undefined;
    const { flow } = await toKeys(world, {
      sync: vi.fn(async (_keys: Keys, onProgress: (done: number) => void) => {
        progress = onProgress;
        await new Promise<void>((resolve) => {
          release = resolve;
        });
      }),
    });
    void flow.confirmKey();
    await settle();
    expect(flow.getState()).toEqual({ status: "copying", done: 0, total: RECORDS.length });
    progress?.(3);
    expect(flow.getState()).toEqual({ status: "copying", done: 3, total: RECORDS.length });
    release?.();
    await settle();
    expect(flow.getState()).toEqual({ status: "done" });
  });

  it("skips the keys when this browser already holds them", async () => {
    const world = worldOf();
    world.keys = { k: "kept" };
    const page = flowWith(world);
    page.flow.start();
    await settle();
    await page.flow.begin();
    await settle();
    expect(page.deps.prepareAccount).not.toHaveBeenCalled();
    expect(page.flow.getState()).toEqual({ status: "done" });
    expect(page.deps.sync).toHaveBeenCalledWith({ k: "kept" }, expect.any(Function));
  });

  it("a reload at each step resumes there and never calls prepareAccount twice", async () => {
    // After the commit, before the flow noted the copy.
    {
      const world = worldOf();
      const first = await toKeys(world, {
        remember: vi.fn(async (step: MigrationStep | null) => {
          if (step === "copying") throw new Error("the tab closed");
          world.step = step;
        }),
      });
      await first.flow.confirmKey();
      await settle();
      expect(world.keys).not.toBeNull();
      expect(world.migrating).toBe(true);

      const again = flowWith(world);
      again.flow.start();
      await settle();
      expect(again.flow.getState()).toEqual({ status: "done" });
      expect(world.prepared).toBe(1);
      expect(again.deps.prepareAccount).not.toHaveBeenCalled();
    }
    // Mid-copy: the copy starts again from a clean slate on both sides.
    {
      const world = worldOf();
      const first = await toKeys(world, {
        sync: vi.fn(async () => {
          world.pushed = 2;
          await new Promise(() => {
            // the tab closes mid-push
          });
        }),
      });
      void first.flow.confirmKey();
      await settle();
      expect(world.step).toBe("copying");

      world.calls = [];
      const again = flowWith(world);
      again.flow.start();
      await settle();
      expect(world.calls).toEqual([
        "loadLocalKeys",
        "start",
        "cancel",
        "resetAll",
        "start",
        "resetAll",
        "source",
        "write",
        "sync",
        "finish",
      ]);
      expect(again.flow.getState()).toEqual({ status: "done" });
      expect(world.prepared).toBe(1);
      // The key's confirmation from the first page is kept.
      const written = (again.deps.write as ReturnType<typeof vi.fn>).mock.calls[0]?.[0] as
        | MigrationRecord[]
        | undefined;
      expect(written?.find((r) => r.type === "settings")?.body).toMatchObject({
        recoveryKeySavedAt: "2026-11-19T10:00:00.000Z",
      });
    }
    // Finishing: everything was pushed, the finish's answer was lost.
    {
      const world = worldOf();
      const first = await toKeys(world, {
        finish: vi.fn(async () => {
          await new Promise(() => {
            // the tab closes while finish runs
          });
        }),
      });
      void first.flow.confirmKey();
      await settle();
      expect(world.step).toBe("finishing");

      world.calls = [];
      const again = flowWith(world);
      again.flow.start();
      await settle();
      expect(world.calls).toEqual(["loadLocalKeys", "start", "source", "sync", "finish"]);
      expect(again.flow.getState()).toEqual({ status: "done" });
      expect(world.prepared).toBe(1);
    }
  });

  it("a reload while the key shows makes a new one: nothing was sent", async () => {
    const world = worldOf();
    const first = await toKeys(world);
    expect(first.flow.getState().status).toBe("keys");
    expect(world.step).toBe("keys");

    const again = flowWith(world);
    again.flow.start();
    await settle();
    expect(again.flow.getState()).toMatchObject({ status: "keys" });
    // One key per page, and only the second is ever committed.
    expect(world.calls.filter((c) => c === "commit")).toEqual([]);
    await again.flow.confirmKey();
    await settle();
    expect(world.calls.filter((c) => c === "commit")).toHaveLength(1);
    expect(again.flow.getState()).toEqual({ status: "done" });
  });

  it("count_mismatch keeps the plaintext: retry calls cancel then resetAll then start", async () => {
    const world = worldOf();
    let refuse = true;
    const { flow, deps } = await toKeys(world, {
      finish: vi.fn(async () => {
        world.calls.push("finish");
        if (refuse) throw fail("count_mismatch");
        world.migrating = false;
      }),
    });
    await flow.confirmKey();
    await settle();
    expect(flow.getState()).toEqual({
      status: "failed",
      problem: "count_mismatch",
      retrying: false,
    });
    // Nothing reloads into the vault, and nothing is cancelled until the person asks.
    expect(deps.reload).not.toHaveBeenCalled();
    expect(deps.cancel).not.toHaveBeenCalled();

    refuse = false;
    world.calls = [];
    flow.retry();
    await settle();
    expect(world.calls).toEqual([
      "cancel",
      "resetAll",
      "start",
      "resetAll",
      "source",
      "write",
      "sync",
      "finish",
    ]);
    // The same keys: no second data key.
    expect(world.prepared).toBe(1);
    expect(flow.getState()).toEqual({ status: "done" });
  });

  it("offline at source leaves migrating and offers retry", async () => {
    const world = worldOf();
    let offline = true;
    const { flow, deps } = await toKeys(world, {
      source: vi.fn(async () => {
        world.calls.push("source");
        if (offline) throw fail("offline");
        return RECORDS.map((r) => ({ ...r }));
      }),
    });
    await flow.confirmKey();
    await settle();
    expect(flow.getState()).toEqual({ status: "failed", problem: "offline", retrying: false });
    expect(world.migrating).toBe(true);
    expect(deps.cancel).not.toHaveBeenCalled();
    expect(deps.write).not.toHaveBeenCalled();

    offline = false;
    flow.retry();
    expect(flow.getState()).toEqual({ status: "failed", problem: "offline", retrying: true });
    await settle();
    expect(flow.getState()).toEqual({ status: "done" });
  });

  it("a failed commit commits the same prepared keys again", async () => {
    const world = worldOf();
    const commit = vi
      .fn<() => Promise<Keys>>()
      .mockRejectedValueOnce(fail("offline"))
      .mockResolvedValue({ k: "dk" });
    const { flow, deps } = await toKeys(world, {
      prepareAccount: vi.fn(async () => ({ recoveryKey: "ABCD-EFGH-JKLM", commit })),
    });
    await flow.confirmKey();
    await settle();
    expect(flow.getState()).toEqual({ status: "failed", problem: "offline", retrying: false });
    flow.retry();
    await settle();
    expect(commit).toHaveBeenCalledTimes(2);
    expect(deps.prepareAccount).toHaveBeenCalledTimes(1);
    expect(deps.cancel).not.toHaveBeenCalled();
    expect(flow.getState()).toEqual({ status: "done" });
  });

  it("in_progress with no local keys shows noLocalVault", async () => {
    const world = worldOf();
    world.migrating = true;
    const { flow, deps } = flowWith(world, {
      prepareAccount: vi.fn(async () => {
        world.calls.push("prepareAccount");
        throw fail("already_set_up");
      }),
    });
    flow.start();
    await settle();
    expect(flow.getState()).toEqual({ status: "noLocalVault", busy: false });
    expect(deps.start).not.toHaveBeenCalled();
    expect(deps.prepareAccount).not.toHaveBeenCalled();

    // "Start again here": takes the move over, cancels it, and asks for the key made elsewhere.
    world.calls = [];
    await flow.restart();
    await settle();
    expect(world.calls).toEqual(["start", "cancel", "resetAll", "start", "prepareAccount"]);
    expect(flow.getState()).toEqual({ status: "unlock" });
    await expect(flow.unlock("ABCD-EFGH-JKLM")).resolves.toBeNull();
    await settle();
    expect(flow.getState()).toEqual({ status: "done" });
  });

  it("409 migration_in_progress shows taken_over", async () => {
    const world = worldOf();
    let taken = true;
    const { flow } = await toKeys(world, {
      sync: vi.fn(async () => {
        world.calls.push("sync");
        if (taken) throw fail("migration_in_progress");
      }),
    });
    await flow.confirmKey();
    await settle();
    expect(flow.getState()).toEqual({ status: "failed", problem: "taken_over", retrying: false });

    // "Continue here" takes the move back for this tab first, then starts the copy over.
    taken = false;
    world.calls = [];
    flow.retry();
    await settle();
    expect(world.calls.slice(0, 4)).toEqual(["start", "cancel", "resetAll", "start"]);
    expect(flow.getState()).toEqual({ status: "done" });
  });

  it("never opens the vault session before done", async () => {
    const world = worldOf();
    const { flow, deps } = await toKeys(world, {
      finish: vi.fn(async () => {
        world.calls.push("finish");
        throw fail("count_mismatch");
      }),
    });
    await flow.confirmKey();
    await settle();
    // A failure never reloads into the vault (the reload is what opens it).
    expect(deps.reload).not.toHaveBeenCalled();

    const ok = worldOf();
    const page = await toKeys(ok);
    await page.flow.confirmKey();
    await settle();
    expect(page.flow.getState()).toEqual({ status: "done" });
    expect(page.deps.reload).not.toHaveBeenCalled();
    page.flow.continue();
    expect(ok.calls.indexOf("reload")).toBeGreaterThan(ok.calls.indexOf("finish"));
    // That no dependency opens the vault session is `local/migration.test.ts`'s to show (its
    // `vault-session.ts` mock throws on any open).
  });

  it("a finish whose answer was lost: the retry reloads into the vault, never resetAll", async () => {
    const world = worldOf();
    const { flow, deps } = await toKeys(world, {
      finish: vi.fn(async () => {
        world.calls.push("finish");
        // The server finished; the answer never arrived.
        world.migrating = false;
        world.encrypted = true;
        throw fail("offline");
      }),
    });
    await flow.confirmKey();
    await settle();
    expect(flow.getState()).toEqual({ status: "failed", problem: "offline", retrying: false });

    world.calls = [];
    flow.retry();
    await settle();
    expect(world.calls).toEqual(["cancel", "accountState", "reload"]);
    expect(world.calls).not.toContain("resetAll");
    expect(deps.reload).toHaveBeenCalledTimes(1);
  });

  it("a second tab's retry after the first tab finished never calls resetAll", async () => {
    const world = worldOf();
    world.keys = { k: "kept" };
    const first = await toKeys(world);
    expect(first.flow.getState()).toEqual({ status: "done" });

    // The second tab of the same browser had failed mid-copy, before the first one finished.
    world.calls = [];
    const second = flowWith(world, { migration: "in_progress" });
    second.flow.start();
    await settle();
    expect(world.calls).toEqual(["loadLocalKeys", "start", "accountState", "reload"]);
    expect(second.deps.resetAll).not.toHaveBeenCalled();
    expect(second.deps.cancel).not.toHaveBeenCalled();
  });

  it("a cancel with nothing to cancel on a plain account: the server failure, no resetAll", async () => {
    const world = worldOf();
    let offline = true;
    const page = flowWith(world, {
      start: vi.fn(async () => {
        world.calls.push("start");
        if (offline) throw fail("offline");
        world.migrating = true;
      }),
    });
    page.flow.start();
    await settle();
    await page.flow.begin();
    await settle();
    expect(page.flow.getState()).toMatchObject({ status: "failed", problem: "offline" });

    offline = false;
    world.calls = [];
    page.flow.retry();
    await settle();
    expect(world.calls).toEqual(["cancel", "accountState"]);
    expect(page.flow.getState()).toEqual({ status: "failed", problem: "server", retrying: false });
    // Its retry loads the page again, so the loaders see the account as it is.
    page.flow.retry();
    await settle();
    expect(world.calls).toEqual(["cancel", "accountState", "reload"]);
    expect(page.deps.resetAll).not.toHaveBeenCalled();
  });

  it("a server error is honest and keeps the plaintext", async () => {
    const world = worldOf();
    const { flow, deps } = await toKeys(world, {
      write: vi.fn(async () => {
        throw new Error("quota");
      }),
    });
    await flow.confirmKey();
    await settle();
    expect(flow.getState()).toEqual({ status: "failed", problem: "server", retrying: false });
    expect(deps.finish).not.toHaveBeenCalled();
  });

  it("another account signed in under this page reloads the app for them", async () => {
    const world = worldOf();
    const page = flowWith(world, {
      start: vi.fn(async () => {
        throw fail("session_changed");
      }),
    });
    page.flow.start();
    await settle();
    await page.flow.begin();
    await settle();
    expect(page.deps.reload).toHaveBeenCalledTimes(1);
    expect(page.deps.prepareAccount).not.toHaveBeenCalled();
  });
});
