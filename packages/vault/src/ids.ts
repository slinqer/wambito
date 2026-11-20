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

/**
 * SHA-1 (FIPS 180-4), synchronous. Only for UUID v5, which RFC 4122 defines over SHA-1: never for
 * anything secret. WebCrypto's digest is async, and awaiting it inside an IndexedDB transaction
 * lets the transaction commit on its own (Firefox does), so the ids are hashed here.
 */
function sha1(data: Uint8Array): Uint8Array {
  const bitLength = data.length * 8;
  const padded = new Uint8Array((((data.length + 8) >> 6) + 1) << 6);
  padded.set(data);
  padded[data.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(padded.length - 8, Math.floor(bitLength / 0x100000000));
  view.setUint32(padded.length - 4, bitLength >>> 0);
  let h0 = 0x67452301;
  let h1 = 0xefcdab89;
  let h2 = 0x98badcfe;
  let h3 = 0x10325476;
  let h4 = 0xc3d2e1f0;
  const w = new Uint32Array(80);
  for (let offset = 0; offset < padded.length; offset += 64) {
    for (let i = 0; i < 16; i++) w[i] = view.getUint32(offset + i * 4);
    for (let i = 16; i < 80; i++) {
      const x = (w[i - 3] ?? 0) ^ (w[i - 8] ?? 0) ^ (w[i - 14] ?? 0) ^ (w[i - 16] ?? 0);
      w[i] = (x << 1) | (x >>> 31);
    }
    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;
    for (let i = 0; i < 80; i++) {
      let f: number;
      let k: number;
      if (i < 20) {
        f = (b & c) | (~b & d);
        k = 0x5a827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }
      const t = (((a << 5) | (a >>> 27)) + f + e + k + (w[i] ?? 0)) >>> 0;
      e = d;
      d = c;
      c = ((b << 30) | (b >>> 2)) >>> 0;
      b = a;
      a = t;
    }
    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
  }
  const out = new Uint8Array(20);
  const outView = new DataView(out.buffer);
  [h0, h1, h2, h3, h4].forEach((h, i) => outView.setUint32(i * 4, h));
  return out;
}

/**
 * A UUID v5 (RFC 4122): SHA-1 of the namespace id and the name. Synchronous, so the local backend
 * can name a record without leaving its IndexedDB transaction.
 */
export function uuidv5Sync(namespace: string, name: string): string {
  const ns = namespace.replaceAll("-", "");
  if (!/^[0-9a-f]{32}$/i.test(ns)) throw new Error("uuidv5: the namespace must be a UUID");
  const nsBytes = Uint8Array.from(ns.match(/../g) ?? [], (h) => Number.parseInt(h, 16));
  const nameBytes = new TextEncoder().encode(name);
  const input = new Uint8Array(nsBytes.length + nameBytes.length);
  input.set(nsBytes);
  input.set(nameBytes, nsBytes.length);
  const digest = sha1(input).slice(0, 16);
  digest[6] = 0x50 | ((digest[6] ?? 0) & 0x0f);
  digest[8] = 0x80 | ((digest[8] ?? 0) & 0x3f);
  return hex(digest);
}

/** `uuidv5Sync` as an already-resolved promise (its callers predate the sync version). */
export function uuidv5(namespace: string, name: string): Promise<string> {
  try {
    return Promise.resolve(uuidv5Sync(namespace, name));
  } catch (error) {
    return Promise.reject(error);
  }
}

/**
 * The UUID v5 namespace of ids derived from an `Idempotency-Key` (`<userId>/<key>/<index>`): a
 * retried batch gets the ids of the first try. Fixed forever; changing it breaks retries in flight.
 */
export const IDEMPOTENCY_NAMESPACE = "6f1d2c3e-8a47-4b59-9c0e-5d7a1b2f4e68";
