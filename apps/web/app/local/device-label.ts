/**
 * A device wrap's label (Ruling 6 of stage 2b): `"<browser> on <OS>"` from the user agent, so the
 * person can tell their browsers apart in Settings → Security; `"Web"` when either is unknown.
 * Order matters: Edge and Opera say "Chrome", Chrome says "Safari", iOS says "Mac OS X" and
 * Android says "Linux".
 */
const BROWSERS: Array<[RegExp, string]> = [
  [/\bEdg(e|A|iOS)?\//, "Edge"],
  [/\b(OPR|Opera)\//, "Opera"],
  [/\bSamsungBrowser\//, "Samsung Internet"],
  [/\b(Firefox|FxiOS)\//, "Firefox"],
  [/\b(Chrome|CriOS|Chromium)\//, "Chrome"],
  [/\bVersion\/[\d.]+.*\bSafari\//, "Safari"],
];

const SYSTEMS: Array<[RegExp, string]> = [
  [/\b(iPhone|iPad|iPod)\b/, "iOS"],
  [/\bAndroid\b/, "Android"],
  [/\bCrOS\b/, "ChromeOS"],
  [/\bWindows\b/, "Windows"],
  [/\b(Macintosh|Mac OS X)\b/, "macOS"],
  [/\bLinux\b/, "Linux"],
];

const first = (list: Array<[RegExp, string]>, userAgent: string) =>
  list.find(([pattern]) => pattern.test(userAgent))?.[1];

export function deviceLabel(userAgent: string): string {
  const browser = first(BROWSERS, userAgent);
  const system = first(SYSTEMS, userAgent);
  return browser && system ? `${browser} on ${system}` : "Web";
}
