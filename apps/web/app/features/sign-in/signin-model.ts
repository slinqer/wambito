import type { PairingClock } from "../../local/relay.ts";
import {
  SigninError,
  type SigninErrorCode,
  type startSignin,
  type WebSignin,
} from "../../local/signin.ts";

/**
 * The QR panel's model (spec 2026-11-15 section 8; web plan rulings 8–10): one sign-in request at
 * a time, renewed at its `expiresAt` while the page is visible, never once the phone answered.
 * Pure: the request maker, the clock and the page's visibility are injected.
 */

export type QrState =
  | { status: "opening" }
  /** A QR and code no phone has answered yet. */
  | { status: "showing"; request: WebSignin }
  /** A phone pinned its key: the number to compare; this request runs to its end. */
  | { status: "approved"; request: WebSignin; number: string }
  /** The phone sealed: picking up, opening and enrolling. */
  | { status: "finishing" }
  | { status: "done"; userId: string }
  /** `too_many` retries by itself at `retryAt`; `expired` renews once the page is visible; the rest wait for `retry()`. */
  | { status: "failed"; code: SigninErrorCode; retryAt?: number }
  /** A hidden page whose request ran out: nothing is open until the page is visible again. */
  | { status: "paused" };

export interface QrSigninDeps {
  start: typeof startSignin;
  /** `deviceLabel(navigator.userAgent)`. */
  label: string;
  clock: PairingClock;
  /** `document.visibilityState === "visible"`. */
  visible(): boolean;
  /** Calls `cb` on every visibility change; returns the unsubscribe. */
  onVisibility(cb: () => void): () => void;
}

export interface QrSignin {
  state(): QrState;
  /** Calls `cb` after every change of `state()` or `remember()`; returns the unsubscribe. */
  subscribe(cb: () => void): () => void;
  /** The box; a change opens a new request after `REMEMBER_DELAY_MS`, never once a number is shown. */
  setRemember(on: boolean): void;
  remember(): boolean;
  /** After a failure (or a paused page): a new request now. */
  retry(): void;
  /** Cancels the request and every timer; nothing opens afterwards. */
  stop(): void;
}

/** How long the box must stay still before its new request opens (ruling 9). */
export const REMEMBER_DELAY_MS = 500;
/** When a 429 names no `retry-after`. */
const DEFAULT_RETRY_MS = 60_000;

const codeOf = (error: unknown): SigninErrorCode =>
  error instanceof SigninError ? error.code : "server";

/** Resolves true at `at` on `clock`, false once `signal` aborts. */
async function waitUntil(clock: PairingClock, at: number, signal: AbortSignal): Promise<boolean> {
  while (!signal.aborted && clock.now() < at) await clock.sleep(at - clock.now(), signal);
  return !signal.aborted;
}

export function createQrSignin(deps: QrSigninDeps): QrSignin {
  const { clock } = deps;
  let state: QrState = { status: "opening" };
  let remember = true;
  let stopped = false;
  /** Every handler checks its generation: a dropped request's answers change nothing. */
  let gen = 0;
  let request: WebSignin | null = null;
  /** The current generation's timers (expiry, retry, the box's delay). */
  let timers = new AbortController();
  const listeners = new Set<() => void>();

  const set = (next: QrState) => {
    state = next;
    for (const cb of [...listeners]) cb();
  };

  /** Cancels the request and its timers; whatever is still in flight becomes stale. */
  const drop = () => {
    gen++;
    timers.abort();
    timers = new AbortController();
    request?.cancel();
    request = null;
  };

  const expired = () => {
    // a hidden page stops; it opens again when it is visible (`onVisible`)
    if (deps.visible()) open();
    else {
      drop();
      set({ status: "paused" });
    }
  };

  const failed = (mine: number, error: unknown) => {
    if (mine !== gen || stopped) return;
    const code = codeOf(error);
    if (code === "cancelled") return;
    if (code === "expired") {
      // an approved request that ran out: visible renews, hidden waits as a failure
      if (deps.visible()) return open();
      drop();
      return set({ status: "failed", code });
    }
    drop();
    if (code === "too_many") {
      const wait =
        error instanceof SigninError && error.retryAfterS !== undefined
          ? error.retryAfterS * 1000
          : DEFAULT_RETRY_MS;
      const retryAt = clock.now() + wait;
      set({ status: "failed", code, retryAt });
      const signal = timers.signal;
      const at = gen;
      void waitUntil(clock, retryAt, signal).then((due) => {
        if (!due || at !== gen || stopped) return;
        if (deps.visible()) open();
        else set({ status: "paused" });
      });
      return;
    }
    set({ status: "failed", code });
  };

  const watch = (mine: number, started: WebSignin) => {
    const signal = timers.signal;
    // ruling 10: replaced at its expiresAt only while no phone answered
    void waitUntil(clock, Date.parse(started.expiresAt), signal).then((due) => {
      if (due && mine === gen && !stopped && state.status === "showing") expired();
    });
    started.number().then(
      (number) => {
        if (mine === gen && !stopped && state.status === "showing") {
          set({ status: "approved", request: started, number });
        }
      },
      (error) => failed(mine, error),
    );
    started.ready().then(
      () => {
        if (mine === gen && !stopped) set({ status: "finishing" });
      },
      (error) => failed(mine, error),
    );
    started.finish().then(
      ({ userId }) => {
        if (mine !== gen || stopped) return;
        request = null;
        set({ status: "done", userId });
      },
      (error) => failed(mine, error),
    );
  };

  function open() {
    if (stopped) return;
    drop();
    const mine = gen;
    set({ status: "opening" });
    deps.start({ remember, label: deps.label, clock }).then(
      (started) => {
        if (mine !== gen || stopped) {
          started.cancel();
          return;
        }
        request = started;
        set({ status: "showing", request: started });
        watch(mine, started);
      },
      (error) => failed(mine, error),
    );
  }

  const onVisible = () => {
    if (stopped || !deps.visible()) return;
    if (state.status === "paused" || (state.status === "failed" && state.code === "expired")) {
      return open();
    }
    // a background tab's timers may fire late: an expired QR is never shown again
    if (state.status === "showing" && clock.now() >= Date.parse(state.request.expiresAt)) {
      expired();
    }
  };
  const unsubscribeVisibility = deps.onVisibility(onVisible);

  if (deps.visible()) open();
  else state = { status: "paused" };

  return {
    state: () => state,
    subscribe(cb) {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    remember: () => remember,
    setRemember(on) {
      if (stopped || on === remember) return;
      const locked =
        state.status === "approved" || state.status === "finishing" || state.status === "done";
      if (locked) return;
      remember = on;
      if (state.status !== "showing" && state.status !== "opening") {
        // a failure or a paused page: the next request takes the new value
        for (const cb of [...listeners]) cb();
        return;
      }
      // the shown QR no longer matches the box: it goes now, the new one after a still moment
      drop();
      const mine = gen;
      set({ status: "opening" });
      void waitUntil(clock, clock.now() + REMEMBER_DELAY_MS, timers.signal).then((due) => {
        if (due && mine === gen) open();
      });
    },
    retry() {
      if (stopped) return;
      if (state.status === "failed" || state.status === "paused") open();
    },
    stop() {
      if (stopped) return;
      drop();
      stopped = true;
      unsubscribeVisibility();
    },
  };
}
