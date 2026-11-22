/** Which of the unlock screen's three layouts applies (spec 2026-11-20, section 1). */
export type UnlockLayout = "key_first" | "passkey_first" | "pair_first";

export interface UnlockLayoutInput {
  /** This device's last passkey touch gave no PRF. */
  noPrfHere: boolean;
  /** The account has a passkey wrap. */
  passkeyWrap: boolean;
  passkeysSupported: boolean;
  /** "From another device" is offered (the consent page has no pairing). */
  canPair: boolean;
}

export interface UnlockPlacement {
  main: "key" | "passkey" | "pair";
  below: Array<"pair">;
  more: Array<"key" | "passkey">;
}

/** What goes where on the unlock screen; pure. */
export function unlockLayout(input: UnlockLayoutInput): UnlockPlacement {
  const { noPrfHere, passkeyWrap, passkeysSupported, canPair } = input;
  const below: Array<"pair"> = canPair ? ["pair"] : [];
  const passkeyWorks = passkeyWrap && passkeysSupported;
  if (noPrfHere) return { main: "key", below, more: passkeyWorks ? ["passkey"] : [] };
  if (passkeyWorks) return { main: "passkey", below, more: ["key"] };
  if (canPair) return { main: "pair", below: [], more: ["key"] };
  return { main: "key", below: [], more: [] };
}
