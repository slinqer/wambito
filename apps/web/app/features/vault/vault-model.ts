/** The pure parts of the recovery-key screens. */

/** How many characters the person types back (spec 7.1). */
export const CONFIRM_COUNT = 4;
/** The 26 data characters; the 27th is the check character, left out of the quiz. */
const DATA_CHARS = 26;

const compact = (key: string) => key.replaceAll("-", "").toUpperCase();

/** Four distinct 1-based positions among the key's data characters, ascending. */
export function pickPositions(): number[] {
  const picked = new Set<number>();
  const random = crypto.getRandomValues(new Uint32Array(64));
  for (const r of random) {
    picked.add((r % DATA_CHARS) + 1);
    if (picked.size === CONFIRM_COUNT) break;
  }
  return [...picked].sort((a, b) => a - b);
}

/** The characters of `key` at 1-based `positions`, dashes ignored. */
export function charsAt(key: string, positions: number[]): string[] {
  const chars = compact(key);
  return positions.map((n) => chars[n - 1] ?? "");
}

/** Same reading as the parser: case-blind, I and L are 1, O is 0. */
const normalize = (c: string) => c.trim().toUpperCase().replace(/[IL]/g, "1").replace(/O/g, "0");

export function confirmationMatches(key: string, positions: number[], typed: string[]): boolean {
  const want = charsAt(key, positions);
  return want.every((c, i) => {
    const got = normalize(typed[i] ?? "");
    return got.length === 1 && got === normalize(c);
  });
}

/** The downloaded file: the key, one line about it and the date. No account data. */
export function recoveryFileText(parts: {
  title: string;
  key: string;
  line: string;
  date: string;
}): string {
  return `${parts.title}\n\n${parts.key}\n\n${parts.line}\n${parts.date}\n`;
}
