export const CONSENT_KEY = "wambito.consent.analytics";
export const CONSENT_VERSION = 1;
export const CONSENT_MAX_AGE_DAYS = 182;

export type ConsentChoice = "granted" | "denied";
export type ConsentState = "ask" | ConsentChoice;
export type BrowserSignals = { globalPrivacyControl?: boolean; doNotTrack?: string | null };

const DAY_MS = 86_400_000;

/** Global Privacy Control or Do Not Track set: the browser already said no. */
export function browserSaysNo(signals: BrowserSignals): boolean {
  return signals.globalPrivacyControl === true || signals.doNotTrack === "1";
}

export function consentState(
  stored: string | null,
  signals: BrowserSignals,
  now: Date,
): ConsentState {
  if (browserSaysNo(signals)) return "denied";
  if (stored === null) return "ask";
  try {
    const value: unknown = JSON.parse(stored);
    if (typeof value !== "object" || value === null) return "ask";
    const { v, choice, at } = value as Record<string, unknown>;
    if (v !== CONSENT_VERSION) return "ask";
    if (choice !== "granted" && choice !== "denied") return "ask";
    if (typeof at !== "string") return "ask";
    const when = Date.parse(at);
    if (Number.isNaN(when)) return "ask";
    if (now.getTime() - when > CONSENT_MAX_AGE_DAYS * DAY_MS) return "ask";
    return choice;
  } catch {
    return "ask";
  }
}

export function encodeChoice(choice: ConsentChoice, now: Date): string {
  return JSON.stringify({ v: CONSENT_VERSION, choice, at: now.toISOString() });
}

export function readStoredConsent(storage: Pick<Storage, "getItem"> | undefined): string | null {
  try {
    return storage?.getItem(CONSENT_KEY) ?? null;
  } catch {
    return null;
  }
}

export function writeStoredConsent(
  storage: Pick<Storage, "setItem"> | undefined,
  value: string,
): boolean {
  try {
    if (!storage) return false;
    storage.setItem(CONSENT_KEY, value);
    return true;
  } catch {
    return false;
  }
}
