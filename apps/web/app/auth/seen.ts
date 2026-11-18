import { API_BASE_URL } from "../api/client.ts";
import { readStored, writeStored } from "../lib/stored.ts";
import { BUILD_ID } from "../site/config.ts";

export interface SeenDeps {
  fetch?: typeof fetch;
  now?: () => Date;
}

/** `YYYY-MM-DD` of `now` in `timeZone` (an unknown zone falls back to UTC). */
function localDay(now: Date, timeZone: string): string {
  const parts = (zone: string) =>
    new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(now);
  try {
    return parts(timeZone);
  } catch {
    return parts("UTC");
  }
}

/**
 * Tells the API the app was opened: once per local day per user (`wambito.seen.<userId>`), a
 * `POST /api/v2/me/seen` with the build id as `x-wambito-version`. Remembered only after a 204,
 * so a failed call is tried again on the next load. Best effort: it never throws.
 */
export async function markSeenToday(
  userId: string,
  timeZone: string,
  deps: SeenDeps = {},
): Promise<void> {
  try {
    const key = `seen.${userId}`;
    const today = localDay((deps.now ?? (() => new Date()))(), timeZone);
    if (readStored(key) === today) return;
    const response = await (deps.fetch ?? fetch)(`${API_BASE_URL}/v2/me/seen`, {
      method: "POST",
      credentials: "same-origin",
      headers: { "x-wambito-version": BUILD_ID },
    });
    if (response.status === 204) writeStored(key, today);
  } catch {
    // Best effort; the next load tries again.
  }
}
