/** Ids of the local backend: lower-case UUID v7 for new records, v5 for recurrence occurrences. */

const hex = (bytes: Uint8Array) => {
  const h = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
};

let lastMs = 0;
let sequence = 0;

/**
 * A UUID v7 (RFC 9562): 48 bits of milliseconds, a 12-bit sequence, 62 random bits. Ids made in
 * the same process always increase, even within one millisecond or if the clock steps back: the
 * sequence counts up (the time borrows a millisecond if it overflows).
 */
export function uuidv7(now: number = Date.now()): string {
  const random = crypto.getRandomValues(new Uint8Array(10));
  if (now > lastMs) {
    lastMs = now;
    // Start below the top so a burst within one millisecond has room to count up.
    sequence = (((random[0] ?? 0) << 8) | (random[1] ?? 0)) & 0x7ff;
  } else {
    sequence += 1;
    if (sequence > 0xfff) {
      lastMs += 1;
      sequence = 0;
    }
  }
  const bytes = new Uint8Array(16);
  let ms = lastMs;
  for (let i = 5; i >= 0; i--) {
    bytes[i] = ms % 256;
    ms = Math.floor(ms / 256);
  }
  bytes[6] = 0x70 | (sequence >> 8);
  bytes[7] = sequence & 0xff;
  bytes[8] = 0x80 | ((random[2] ?? 0) & 0x3f);
  for (let i = 3; i < 10; i++) bytes[6 + i] = random[i] ?? 0;
  return hex(bytes);
}

/** A UUID v5 (RFC 4122): SHA-1 of the namespace id and the name. Async, WebCrypto has no sync hash. */
export async function uuidv5(namespace: string, name: string): Promise<string> {
  const ns = namespace.replaceAll("-", "");
  if (!/^[0-9a-f]{32}$/i.test(ns)) throw new Error("uuidv5: the namespace must be a UUID");
  const nsBytes = Uint8Array.from(ns.match(/../g) ?? [], (h) => Number.parseInt(h, 16));
  const nameBytes = new TextEncoder().encode(name);
  const input = new Uint8Array(nsBytes.length + nameBytes.length);
  input.set(nsBytes);
  input.set(nameBytes, nsBytes.length);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", input)).slice(0, 16);
  digest[6] = 0x50 | ((digest[6] ?? 0) & 0x0f);
  digest[8] = 0x80 | ((digest[8] ?? 0) & 0x3f);
  return hex(digest);
}
