import type { WrapDto } from "../../local/keys.ts";
import type { PasskeyItem } from "./passkeys.ts";

/**
 * Settings → Security's rows (stage 2b Task 8), from `GET /v2/keys`, this browser's meta
 * (`deviceWrapId`), `settings.revokedDevices`, the attestation checks and the passkey list. Pure:
 * the screen loads the inputs (`security.ts`).
 */

/** A wrap as `GET /v2/keys` lists it, with when it was added. */
export type SecurityWrap = WrapDto & { createdAt?: string | null };

export interface DeviceRow {
  id: string;
  label: string | null;
  createdAt: string | null;
  /** This browser's own device: marked, and never removable from here. */
  thisBrowser: boolean;
  /** Its attestation checks out under the data key; else shown as "Not verified". */
  verified: boolean;
  removable: boolean;
}

export interface PasskeyRow extends PasskeyItem {
  /** Whether a passkey wrap has this credential as `ref`; null when the wraps are unknown. */
  unlocks: boolean | null;
}

const byAdded = (a: DeviceRow, b: DeviceRow) =>
  (a.createdAt ?? "") < (b.createdAt ?? "")
    ? -1
    : (a.createdAt ?? "") > (b.createdAt ?? "")
      ? 1
      : 0;

/**
 * This browser's device and the others, oldest first. Revoked ids (removed earlier, whatever the
 * server still lists) are left out; a device whose attestation failed can only be removed.
 */
export function deviceRows(input: {
  wraps: readonly SecurityWrap[];
  ownId: string | null;
  revoked: readonly string[];
  /** Device wrap ids whose attestation checked out. */
  verified: ReadonlySet<string>;
}): { thisBrowser: DeviceRow | null; others: DeviceRow[] } {
  const revoked = new Set(input.revoked);
  let thisBrowser: DeviceRow | null = null;
  const others: DeviceRow[] = [];
  for (const wrap of input.wraps) {
    if (wrap.kind !== "device" || revoked.has(wrap.id)) continue;
    const own = wrap.id === input.ownId;
    const row: DeviceRow = {
      id: wrap.id,
      label: wrap.label ?? null,
      createdAt: wrap.createdAt ?? null,
      thisBrowser: own,
      // this browser's own wrap opened the data key here: nothing to check
      verified: own || input.verified.has(wrap.id),
      removable: !own,
    };
    if (own) thisBrowser = row;
    else others.push(row);
  }
  return { thisBrowser, others: others.sort(byAdded) };
}

/** Each passkey with whether its wrap exists (joined by credential id, the wrap's `ref`). */
export function passkeyRows(
  passkeys: readonly PasskeyItem[],
  wraps: readonly SecurityWrap[] | undefined,
): PasskeyRow[] {
  const refs = wraps
    ? new Set(wraps.filter((w) => w.kind === "passkey" && w.ref).map((w) => w.ref as string))
    : null;
  return passkeys.map((item) => ({
    ...item,
    unlocks: refs ? refs.has(item.credentialId) : null,
  }));
}
