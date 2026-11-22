/**
 * The sources a capture can come from: Android reads the first two from notifications, iOS gets
 * `apple_wallet` from the Shortcuts Transaction automation. Only a new capture is checked against
 * this list; a stored transaction keeps any source text, so a newer client's source never breaks
 * an older one (records.ts, schemas.ts).
 */
export const CAPTURE_SOURCES = ["revolut", "google_wallet", "apple_wallet"] as const;
export type CaptureSource = (typeof CAPTURE_SOURCES)[number];

/** Whether this version knows [source] (a stored one may come from a newer client). */
export function isCaptureSource(source: string | null | undefined): source is CaptureSource {
  return (CAPTURE_SOURCES as readonly string[]).includes(source ?? "");
}
