/**
 * Per-address limits kept in process memory: no IP address is ever written to the database (spec
 * §9). One instance per app; a restart forgets every count, which only loosens a limit briefly.
 */

/** A request's address, or one shared bucket for requests without a trusted address. */
const bucket = (ip: string | null) => ip ?? "unknown";

/** Fixed-window request counter per address. */
export class IpWindowLimit {
  readonly #windows = new Map<string, { opened: number; count: number }>();

  constructor(private readonly limit: { max: number; windowMs: number }) {}

  /** Counts one request and returns true when it goes over the limit. */
  hit(ip: string | null, now: number): boolean {
    this.#sweep(now);
    const key = bucket(ip);
    const w = this.#windows.get(key);
    if (!w || now - w.opened >= this.limit.windowMs) {
      this.#windows.set(key, { opened: now, count: 1 });
      return 1 > this.limit.max;
    }
    w.count += 1;
    return w.count > this.limit.max;
  }

  /** Drops expired windows so the map holds only addresses seen within one window. */
  #sweep(now: number): void {
    for (const [key, w] of this.#windows) {
      if (now - w.opened >= this.limit.windowMs) this.#windows.delete(key);
    }
  }
}

/** The ids an address holds open at once, each until its expiry. */
export class IpOpenCount {
  readonly #open = new Map<string, { bucket: string; expiresAt: number }>();

  constructor(private readonly max: number) {}

  /** Opens `id` for `ip` until `expiresAt`; false when the address already holds `max` unexpired. */
  tryOpen(ip: string | null, id: string, expiresAt: number, now: number): boolean {
    const key = bucket(ip);
    let held = 0;
    for (const [openId, o] of this.#open) {
      if (o.expiresAt <= now) this.#open.delete(openId);
      else if (o.bucket === key) held += 1;
    }
    if (held >= this.max) return false;
    this.#open.set(id, { bucket: key, expiresAt });
    return true;
  }

  close(id: string): void {
    this.#open.delete(id);
  }
}
