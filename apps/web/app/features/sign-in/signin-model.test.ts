import { describe, expect, it, vi } from "vitest";
import type { PairingClock } from "../../local/relay.ts";
import { SigninError, type WebSignin } from "../../local/signin.ts";
import { createQrSignin, type QrState, REMEMBER_DELAY_MS } from "./signin-model.ts";

const T0 = Date.parse("2026-11-18T12:00:00Z");
const TTL = 2 * 60 * 1000;

const flush = async () => {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
};

/** A clock that moves only when the test says, waking each sleeper at its time. */
function fakeClock() {
  let now = T0;
  const sleepers: Array<{ at: number; wake: () => void }> = [];
  const clock: PairingClock = {
    now: () => now,
    sleep: (ms, signal) =>
      new Promise<void>((resolve) => {
        const sleeper = { at: now + ms, wake: resolve };
        sleepers.push(sleeper);
        signal.addEventListener("abort", () => {
          sleepers.splice(sleepers.indexOf(sleeper), 1);
          resolve();
        });
      }),
  };
  return {
    clock,
    /** Moves time on by `ms`, waking each sleeper due on the way, in order. */
    async advance(ms: number) {
      const target = now + ms;
      for (;;) {
        await flush();
        const due = sleepers.filter((s) => s.at <= target).sort((a, b) => a.at - b.at)[0];
        if (!due) break;
        sleepers.splice(sleepers.indexOf(due), 1);
        now = Math.max(now, due.at);
        due.wake();
      }
      now = target;
      await flush();
    },
    /** Time passes with no timer firing (a background tab's throttled timers). */
    jump(ms: number) {
      now += ms;
    },
  };
}

type FakeRequest = WebSignin & {
  remember: boolean;
  label: string;
  cancel: ReturnType<typeof vi.fn>;
  approve(number: string): void;
  makeReady(): void;
  succeed(userId: string): void;
  fail(error: unknown): void;
};

/** `startSignin` stand-in: each call makes a request the test drives like the phone would. */
function fakeStart(clock: PairingClock) {
  const requests: FakeRequest[] = [];
  let failNext: unknown = null;
  const start = vi.fn(async (options: { remember: boolean; label: string }) => {
    if (failNext) {
      const error = failNext;
      failNext = null;
      throw error;
    }
    let resolveNumber!: (n: string) => void;
    let resolveReady!: () => void;
    let resolveFinish!: (v: { userId: string; keys: never }) => void;
    let rejectAll!: (error: unknown) => void;
    const numberP = new Promise<string>((res, rej) => {
      resolveNumber = res;
      const prev = rejectAll;
      rejectAll = (e) => {
        prev?.(e);
        rej(e);
      };
    });
    const readyP = new Promise<void>((res, rej) => {
      resolveReady = res;
      const prev = rejectAll;
      rejectAll = (e) => {
        prev(e);
        rej(e);
      };
    });
    const finishP = new Promise<{ userId: string; keys: never }>((res, rej) => {
      resolveFinish = res;
      const prev = rejectAll;
      rejectAll = (e) => {
        prev(e);
        rej(e);
      };
    });
    for (const p of [numberP, readyP, finishP]) p.catch(() => {});
    const n = requests.length + 1;
    const request: FakeRequest = {
      id: `0190a1b2-c3d4-7e5f-8a9b-${String(n).padStart(12, "0")}`,
      code: `ABCDEFG${n % 10}`,
      qr: `wambito://signin?id=${n}&key=k`,
      expiresAt: new Date(clock.now() + TTL).toISOString(),
      remember: options.remember,
      label: options.label,
      number: () => numberP,
      ready: () => readyP,
      finish: () => finishP,
      cancel: vi.fn(() => rejectAll(new SigninError("cancelled"))),
      approve: (number) => resolveNumber(number),
      makeReady: () => resolveReady(),
      succeed: (userId) => resolveFinish({ userId, keys: undefined as never }),
      fail: (error) => rejectAll(error),
    };
    requests.push(request);
    return request;
  });
  return {
    start,
    requests,
    failOnce(error: unknown) {
      failNext = error;
    },
  };
}

/** A page whose visibility the test flips. */
function fakePage(initial = true) {
  let visible = initial;
  const listeners = new Set<() => void>();
  return {
    visible: () => visible,
    onVisibility(cb: () => void) {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    set(on: boolean) {
      visible = on;
      for (const cb of listeners) cb();
    },
    listeners,
  };
}

function setup(visible = true) {
  const time = fakeClock();
  const fake = fakeStart(time.clock);
  const page = fakePage(visible);
  const model = createQrSignin({
    start: fake.start as never,
    label: "Firefox on macOS",
    clock: time.clock,
    visible: page.visible,
    onVisibility: page.onVisibility,
  });
  const states: QrState[] = [];
  model.subscribe(() => states.push(model.state()));
  return { time, fake, page, model, states };
}

describe("createQrSignin", () => {
  it("opens one request at once with remember true and the label", async () => {
    const { fake, model } = setup();
    expect(model.remember()).toBe(true);
    expect(model.state().status).toBe("opening");
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(1);
    expect(fake.start.mock.calls[0]?.[0]).toMatchObject({
      remember: true,
      label: "Firefox on macOS",
    });
    const state = model.state();
    expect(state.status).toBe("showing");
    if (state.status === "showing") expect(state.request).toBe(fake.requests[0]);
  });

  it("at expiresAt while visible it opens exactly one new request and cancels the old", async () => {
    const { time, fake, model } = setup();
    await flush();
    await time.advance(TTL - 1);
    expect(fake.start).toHaveBeenCalledTimes(1);
    await time.advance(1);
    expect(fake.requests[0]?.cancel).toHaveBeenCalled();
    expect(fake.start).toHaveBeenCalledTimes(2);
    const state = model.state();
    expect(state.status === "showing" && state.request).toBe(fake.requests[1]);
    // the old request's own expiry (its finish() rejecting) changes nothing more
    fake.requests[0]?.fail(new SigninError("expired"));
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(2);
  });

  it("hidden: it stops at expiry and opens nothing; visible again: exactly one new request, never the expired QR", async () => {
    const { time, fake, model, page, states } = setup();
    await flush();
    page.set(false);
    await time.advance(TTL);
    expect(fake.requests[0]?.cancel).toHaveBeenCalled();
    expect(model.state().status).toBe("paused");
    await time.advance(10 * TTL);
    expect(fake.start).toHaveBeenCalledTimes(1);
    states.length = 0;
    page.set(true);
    page.set(true);
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(2);
    // straight from paused to opening: the expired request is never shown again
    expect(states.every((s) => s.status !== "showing" || s.request === fake.requests[1])).toBe(
      true,
    );
    const state = model.state();
    expect(state.status === "showing" && state.request).toBe(fake.requests[1]);
  });

  it("hidden with throttled timers: shown again past expiresAt, it renews at once instead of showing the old QR", async () => {
    const { time, fake, model, page } = setup();
    await flush();
    page.set(false);
    time.jump(TTL + 5000);
    page.set(true);
    expect(model.state().status).toBe("opening");
    expect(fake.requests[0]?.cancel).toHaveBeenCalled();
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(2);
    const state = model.state();
    expect(state.status === "showing" && state.request).toBe(fake.requests[1]);
    // the old timer firing late opens nothing more
    await time.advance(1);
    expect(fake.start).toHaveBeenCalledTimes(2);
  });

  it("a request whose number() resolved is never replaced at expiresAt; finish() runs to done", async () => {
    const { time, fake, model } = setup();
    await flush();
    await time.advance(TTL - 10);
    fake.requests[0]?.approve("042917");
    await flush();
    const approved = model.state();
    expect(approved.status).toBe("approved");
    if (approved.status === "approved") expect(approved.number).toBe("042917");
    await time.advance(10_000);
    expect(fake.start).toHaveBeenCalledTimes(1);
    expect(fake.requests[0]?.cancel).not.toHaveBeenCalled();
    fake.requests[0]?.makeReady();
    await flush();
    expect(model.state().status).toBe("finishing");
    fake.requests[0]?.succeed("user-1");
    await flush();
    expect(model.state()).toEqual({ status: "done", userId: "user-1" });
  });

  it("unticking opens a new request with remember false after 500 ms; two toggles within 500 ms open one", async () => {
    const { time, fake, model } = setup();
    await flush();
    model.setRemember(false);
    expect(model.remember()).toBe(false);
    // the shown QR no longer matches the box: it goes at once
    expect(fake.requests[0]?.cancel).toHaveBeenCalled();
    expect(model.state().status).toBe("opening");
    await time.advance(REMEMBER_DELAY_MS - 1);
    expect(fake.start).toHaveBeenCalledTimes(1);
    await time.advance(1);
    expect(fake.start).toHaveBeenCalledTimes(2);
    expect(fake.requests[1]?.remember).toBe(false);
    expect(REMEMBER_DELAY_MS).toBe(500);

    model.setRemember(true);
    await time.advance(200);
    model.setRemember(false);
    await time.advance(REMEMBER_DELAY_MS - 1);
    expect(fake.start).toHaveBeenCalledTimes(2);
    await time.advance(1);
    expect(fake.start).toHaveBeenCalledTimes(3);
    expect(fake.requests[2]?.remember).toBe(false);
    await time.advance(5000);
    expect(fake.start).toHaveBeenCalledTimes(3);
  });

  it("the box cannot change once a number is shown", async () => {
    const { time, fake, model } = setup();
    await flush();
    fake.requests[0]?.approve("042917");
    await flush();
    model.setRemember(false);
    expect(model.remember()).toBe(true);
    await time.advance(REMEMBER_DELAY_MS * 2);
    expect(fake.start).toHaveBeenCalledTimes(1);
    expect(fake.requests[0]?.cancel).not.toHaveBeenCalled();
    expect(model.state().status).toBe("approved");
  });

  it("too_many shows failed with retryAt and retries by itself at retryAt", async () => {
    const { time, fake, model } = setup(true);
    await flush();
    fake.failOnce(new SigninError("too_many", 42));
    await time.advance(TTL);
    expect(model.state()).toEqual({
      status: "failed",
      code: "too_many",
      retryAt: T0 + TTL + 42_000,
    });
    await time.advance(42_000 - 1);
    expect(fake.start).toHaveBeenCalledTimes(2);
    await time.advance(1);
    expect(fake.start).toHaveBeenCalledTimes(3);
    expect(model.state().status).toBe("showing");
  });

  it("other failures wait for retry(); a failed expired while visible renews by itself", async () => {
    const { fake, model } = setup();
    await flush();
    fake.requests[0]?.fail(new SigninError("offline"));
    await flush();
    expect(model.state()).toEqual({ status: "failed", code: "offline" });
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(1);
    model.retry();
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(2);
    expect(model.state().status).toBe("showing");

    // an approved request that runs out renews by itself while the page is visible
    fake.requests[1]?.approve("042917");
    await flush();
    fake.requests[1]?.fail(new SigninError("expired"));
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(3);
    expect(model.state().status).toBe("showing");

    // anything that is not a SigninError (the enroll's KeysError) is shown as server
    fake.requests[2]?.fail(new Error("boom"));
    await flush();
    expect(model.state()).toEqual({ status: "failed", code: "server" });
  });

  it("stop() cancels the request and opens nothing more", async () => {
    const { time, fake, model, page } = setup();
    await flush();
    model.stop();
    expect(fake.requests[0]?.cancel).toHaveBeenCalled();
    expect(page.listeners.size).toBe(0);
    model.setRemember(false);
    model.retry();
    page.set(true);
    await time.advance(10 * TTL);
    expect(fake.start).toHaveBeenCalledTimes(1);
  });

  it("stop() while a request is opening cancels it when it arrives", async () => {
    const { fake, model } = setup();
    model.stop();
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(1);
    expect(fake.requests[0]?.cancel).toHaveBeenCalled();
    expect(model.state().status).not.toBe("showing");
  });

  it("opened while hidden it waits, and opens once the page is visible", async () => {
    const { fake, model, page } = setup(false);
    await flush();
    expect(fake.start).not.toHaveBeenCalled();
    expect(model.state().status).toBe("paused");
    page.set(true);
    await flush();
    expect(fake.start).toHaveBeenCalledTimes(1);
  });
});
