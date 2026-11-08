// Writes ../test-vectors.json from fixed inputs. Run: pnpm --filter @wambito/crypto vectors
// (node --experimental-strip-types). Everything is deterministic, so a second run changes nothing.
// Device seals need an ephemeral key; here it comes from a fixed seed through @noble/curves, in
// this script only, so the public API keeps generating a random one.
import { writeFileSync } from "node:fs";
import { x25519 } from "@noble/curves/ed25519.js";
import {
  toBase64Url as b64,
  deriveRecordKeys,
  deviceAttestation,
  formatRecoveryKey,
  importDevicePrivateKey,
  pairingCommitment,
  pairingNumber,
  sealRecord,
  sealToDevice,
  wrapDataKey,
} from "../src/index.ts";
import { dedupeTag } from "../src/records.ts";
import { deriveWrapKey, gcmSeal, type WrapContext, wrapAssociatedData } from "../src/wraps.ts";

/** `len` bytes: seed, seed+1, ... (wraps at 256). Never use for real keys. */
function fixed(seed: number, len: number): Uint8Array {
  return Uint8Array.from({ length: len }, (_, i) => (seed + i) & 255);
}

// Better Auth shaped ids (invented): mixed case, case is significant.
const USER = "kX3mQ9vTz2LpR8wYb5NcHd7JfA1sUe4B";
const USER_2 = "Zq8Rt2WnY5vLc1MbXe9HjD4sAf7GuK0p";
const ID_1 = "0194f3a2-8c00-7000-8000-000000000001";
const ID_2 = "0194f3a2-8c00-7000-8000-000000000002";
const ID_3 = "0194f3a2-8c00-7000-8000-000000000003";

const dataKeyA = fixed(0x10, 32);
const dataKeyB = fixed(0x80, 32);

// Exactly 64 bytes as JSON (62 characters plus the two quotes): no padding is added.
const exact64 = "x".repeat(62);

const recordInputs = [
  {
    dataKey: dataKeyA,
    ctx: { userId: USER, type: "transaction", id: ID_1, keyV: 1 },
    nonce: fixed(0x01, 12),
    value: { amountCents: -1850000, note: "almuerzo", occurredOn: "2026-11-08" },
    dedupeText: "Almuerzo Corrientazo",
  },
  {
    dataKey: dataKeyA,
    ctx: { userId: USER, type: "category", id: ID_2, keyV: 1 },
    nonce: fixed(0x21, 12),
    value: { name: "Café y ñandúes ☕ 食べ物", emoji: "🥐" },
    dedupeText: "Café y ñandúes",
  },
  {
    dataKey: dataKeyB,
    ctx: { userId: USER_2, type: "settings", id: ID_3, keyV: 32767 },
    nonce: fixed(0x41, 12),
    value: exact64,
    dedupeText: "",
  },
  {
    dataKey: dataKeyB,
    ctx: { userId: USER_2, type: "budget", id: ID_1, keyV: 0 },
    nonce: fixed(0x61, 12),
    value: { categoryId: ID_2, month: "2026-11", limitCents: 25000000, tags: [] },
    dedupeText: "budget 2026-11",
  },
] as const;

const records = [];
for (const r of recordInputs) {
  const keys = await deriveRecordKeys(r.dataKey);
  records.push({
    dataKey: b64(r.dataKey),
    ctx: r.ctx,
    nonce: b64(r.nonce),
    value: r.value,
    body: b64(await sealRecord(keys, r.ctx, r.value, r.nonce)),
    dedupe: { text: r.dedupeText, tag: await dedupeTag(keys, r.dedupeText) },
  });
}

const wrapInputs: {
  secret: Uint8Array;
  ctx: WrapContext;
  nonce: Uint8Array;
  dataKey: Uint8Array;
}[] = [
  {
    secret: fixed(0x30, 32),
    ctx: { kind: "passkey", userId: USER, keyV: 1 },
    nonce: fixed(0x02, 12),
    dataKey: dataKeyA,
  },
  {
    secret: fixed(0x50, 16),
    ctx: { kind: "recovery", userId: USER, keyV: 1 },
    nonce: fixed(0x22, 12),
    dataKey: dataKeyA,
  },
  {
    secret: fixed(0x70, 32),
    ctx: { kind: "assistant", userId: USER_2, keyV: 7 },
    nonce: fixed(0x42, 12),
    dataKey: dataKeyB,
  },
];
const wraps = [];
for (const w of wrapInputs) {
  wraps.push({
    secret: b64(w.secret),
    ctx: w.ctx,
    nonce: b64(w.nonce),
    dataKey: b64(w.dataKey),
    wrapped: b64(await wrapDataKey(w.secret, w.ctx, w.dataKey, w.nonce)),
  });
}

const recovery = [
  fixed(0x00, 16),
  fixed(0xf0, 16),
  new Uint8Array(16),
  new Uint8Array(16).fill(255),
].map((secret) => ({ secret: b64(secret), text: formatRecoveryKey(secret) }));

// Same format as sealToDevice (ephemeral public key || nonce || GCM), with a fixed ephemeral.
const deviceInputs = [
  {
    priv: fixed(0x90, 32),
    eph: fixed(0xa0, 32),
    nonce: fixed(0x03, 12),
    dataKey: dataKeyA,
    ctx: { kind: "device", userId: USER, keyV: 1 },
  },
  {
    priv: fixed(0xb0, 32),
    eph: fixed(0xc0, 32),
    nonce: fixed(0x23, 12),
    dataKey: dataKeyB,
    ctx: { kind: "device", userId: USER_2, keyV: 3 },
  },
] as const;
const devices = [];
for (const d of deviceInputs) {
  const publicKey = x25519.getPublicKey(d.priv);
  const shared = x25519.getSharedSecret(d.eph, publicKey);
  const inner = await gcmSeal(
    await deriveWrapKey(shared, "device"),
    wrapAssociatedData(d.ctx),
    d.dataKey,
    d.nonce,
  );
  const sealed = new Uint8Array(32 + inner.length);
  sealed.set(x25519.getPublicKey(d.eph));
  sealed.set(inner, 32);
  devices.push({
    privateKey: b64(d.priv),
    publicKey: b64(publicKey),
    ctx: d.ctx,
    sealed: b64(sealed),
    dataKey: b64(d.dataKey),
  });
}

const keyA = x25519.getPublicKey(fixed(0x90, 32));
const keyB = x25519.getPublicKey(fixed(0xb0, 32));
const pairing = [];
for (const [a, c] of [
  [keyA, keyB],
  [keyB, keyA],
  [keyA, keyA],
] as const) {
  pairing.push({ a: b64(a), b: b64(c), number: await pairingNumber(a, c) });
}

// Pairing with a commitment: N is the new device, A the approver's ephemeral pair. `sealed` comes
// from the public sealToDevice with A as the given ephemeral key; its nonce is random, so the file
// stores one fixed result made here with a fixed nonce (same bytes as sealToDevice would produce).
const approvalInputs = [
  {
    newPriv: fixed(0xd0, 32),
    approverPriv: fixed(0xe0, 32),
    nonce: fixed(0x04, 12),
    dataKey: dataKeyA,
    ctx: { kind: "device", userId: USER, keyV: 1 },
  },
  {
    newPriv: fixed(0x05, 32),
    approverPriv: fixed(0x15, 32),
    nonce: fixed(0x24, 12),
    dataKey: dataKeyB,
    ctx: { kind: "device", userId: USER_2, keyV: 4 },
  },
] as const;
const approvals = [];
for (const p of approvalInputs) {
  const newPub = x25519.getPublicKey(p.newPriv);
  const approverPub = x25519.getPublicKey(p.approverPriv);
  const inner = await gcmSeal(
    await deriveWrapKey(x25519.getSharedSecret(p.approverPriv, newPub), "device"),
    wrapAssociatedData(p.ctx),
    p.dataKey,
    p.nonce,
  );
  const sealed = new Uint8Array(32 + inner.length);
  sealed.set(approverPub);
  sealed.set(inner, 32);
  // The public API with a given ephemeral must agree on everything but the random nonce.
  const viaApi = await sealToDevice(newPub, p.ctx, p.dataKey, {
    publicKey: approverPub,
    privateKey: await importDevicePrivateKey(p.approverPriv),
  });
  if (b64(viaApi.slice(0, 32)) !== b64(approverPub)) throw new Error("ephemeral not used");
  approvals.push({
    newPrivateKey: b64(p.newPriv),
    newPublicKey: b64(newPub),
    commitment: b64(await pairingCommitment(newPub)),
    approverPrivateKey: b64(p.approverPriv),
    approverPublicKey: b64(approverPub),
    number: await pairingNumber(newPub, approverPub),
    ctx: p.ctx,
    sealed: b64(sealed),
    dataKey: b64(p.dataKey),
  });
}

const attestationInputs = [
  { dataKey: dataKeyA, userId: USER, wrapId: ID_1, publicKey: keyA },
  { dataKey: dataKeyB, userId: USER_2, wrapId: ID_3, publicKey: keyB },
];
const attestations = [];
for (const a of attestationInputs) {
  attestations.push({
    dataKey: b64(a.dataKey),
    userId: a.userId,
    wrapId: a.wrapId,
    publicKey: b64(a.publicKey),
    attestation: b64(await deviceAttestation(a.dataKey, a)),
  });
}

// Inputs every implementation must refuse.
const okRecord = recordInputs[0];
const okRecovery = recovery[0]?.text ?? "";
const lastChar = okRecovery.slice(-1);
const changed = okRecovery.slice(0, -1) + (lastChar === "0" ? "1" : "0");
const rejects = [
  {
    name: "record with a user id containing a slash",
    op: "sealRecord",
    dataKey: b64(okRecord.dataKey),
    ctx: { ...okRecord.ctx, userId: `${USER.slice(0, 10)}/${USER.slice(11)}` },
    nonce: b64(okRecord.nonce),
    value: okRecord.value,
    code: "bad_input",
  },
  {
    name: "record with an upper-case record id",
    op: "sealRecord",
    dataKey: b64(okRecord.dataKey),
    ctx: { ...okRecord.ctx, id: okRecord.ctx.id.toUpperCase() },
    nonce: b64(okRecord.nonce),
    value: okRecord.value,
    code: "bad_input",
  },
  {
    name: "record with an 11-byte nonce",
    op: "sealRecord",
    dataKey: b64(okRecord.dataKey),
    ctx: okRecord.ctx,
    nonce: b64(okRecord.nonce.slice(0, 11)),
    value: okRecord.value,
    code: "bad_input",
  },
  {
    name: "recovery key with one character changed",
    op: "parseRecoveryKey",
    text: changed,
    code: "bad_recovery_key",
  },
  {
    name: "recovery wrap with a 15-byte secret",
    op: "wrapDataKey",
    secret: b64(fixed(0x50, 15)),
    ctx: { kind: "recovery", userId: USER, keyV: 1 },
    nonce: b64(fixed(0x22, 12)),
    dataKey: b64(dataKeyA),
    code: "bad_input",
  },
  {
    name: "pairing blob sealed with a different ephemeral key than the approver key",
    op: "openFromPairing",
    privateKey: approvals[0]?.newPrivateKey,
    ctx: approvals[0]?.ctx,
    sealed: approvals[0]?.sealed,
    approverKey: b64(keyA),
    code: "cannot_open",
  },
];

const out = {
  _about:
    "Shared test vectors for packages/crypto (bytes are base64url). The Dart port must pass them byte for byte. Never edit by hand: regenerate with `pnpm --filter @wambito/crypto vectors`.",
  records,
  wraps,
  recovery,
  devices,
  pairing,
  approvals,
  attestations,
  rejects,
};
writeFileSync(
  new URL("../test-vectors.json", import.meta.url),
  `${JSON.stringify(out, null, 2)}\n`,
);
