import { describe, expect, it } from "vitest";
import type { PasskeyItem } from "./passkeys.ts";
import { deviceRows, passkeyRows, type SecurityWrap } from "./security-model.ts";

const wrap = (over: Partial<SecurityWrap> & { id: string; kind: string }): SecurityWrap => ({
  ref: null,
  keyV: 2,
  wrapped: "w",
  publicKey: null,
  attestation: null,
  label: null,
  createdAt: "2026-10-01T10:00:00.000Z",
  ...over,
});

const OWN = "01930000-0000-7000-8000-00000000000a";
const LAPTOP = "01930000-0000-7000-8000-00000000000b";
const FORGED = "01930000-0000-7000-8000-00000000000c";
const GONE = "01930000-0000-7000-8000-00000000000d";

const wraps: SecurityWrap[] = [
  wrap({ id: "r", kind: "recovery" }),
  wrap({
    id: LAPTOP,
    kind: "device",
    label: "Firefox on Linux",
    createdAt: "2026-10-03T10:00:00Z",
  }),
  wrap({ id: OWN, kind: "device", label: "Chrome on macOS", createdAt: "2026-10-02T10:00:00Z" }),
  wrap({ id: FORGED, kind: "device", label: "Safari on iOS", createdAt: "2026-10-04T10:00:00Z" }),
  wrap({ id: GONE, kind: "device", label: "Edge on Windows" }),
  wrap({ id: "p1", kind: "passkey", ref: "cred-1" }),
];

const rows = () =>
  deviceRows({ wraps, ownId: OWN, revoked: [GONE], verified: new Set([LAPTOP, GONE]) });

const passkey = (id: string, credentialId: string): PasskeyItem => ({
  id,
  credentialId,
  name: null,
  createdAt: "2026-10-02T09:00:00.000Z",
  synced: true,
});

describe("deviceRows", () => {
  it("this browser's device is marked and cannot be removed here", () => {
    const { thisBrowser, others } = rows();
    expect(thisBrowser).toMatchObject({
      id: OWN,
      label: "Chrome on macOS",
      thisBrowser: true,
      removable: false,
    });
    expect(others.map((d) => d.id)).not.toContain(OWN);
    expect(others.every((d) => !d.thisBrowser && d.removable)).toBe(true);
  });

  it('a device whose attestation fails is shown as "Not verified" with remove only', () => {
    const forged = rows().others.find((d) => d.id === FORGED);
    expect(forged).toMatchObject({ verified: false, removable: true });
    expect(rows().others.find((d) => d.id === LAPTOP)).toMatchObject({ verified: true });
    // this browser's own wrap needs no check: it opened DK here
    expect(rows().thisBrowser?.verified).toBe(true);
  });

  it("revoked ids are not listed", () => {
    const { thisBrowser, others } = rows();
    expect([thisBrowser?.id, ...others.map((d) => d.id)]).not.toContain(GONE);
    // only device wraps are devices, oldest first
    expect(others.map((d) => d.id)).toEqual([LAPTOP, FORGED]);
  });

  it("without this browser's wrap there is no row for it", () => {
    const { thisBrowser } = deviceRows({ wraps, ownId: null, revoked: [], verified: new Set() });
    expect(thisBrowser).toBeNull();
  });
});

describe("passkeyRows", () => {
  it("passkeys join their wrap by credential id", () => {
    const joined = passkeyRows([passkey("pk-1", "cred-1"), passkey("pk-2", "cred-2")], wraps);
    expect(joined.map((p) => [p.id, p.unlocks])).toEqual([
      ["pk-1", true],
      ["pk-2", false],
    ]);
  });

  it("unknown wraps (not loaded, or a plain account) say nothing about unlocking", () => {
    const joined = passkeyRows([passkey("pk-1", "cred-1")], undefined);
    expect(joined[0]?.unlocks).toBeNull();
  });
});
