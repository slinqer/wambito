import { CROCKFORD } from "@wambito/crypto";

/** A full key: 26 data characters and a check character, shown in groups of four. */
const KEY_CHARS = 27;
const GROUP = 4;
/** The key's alphabet plus the look-alikes the parser forgives (O, I, L). */
const ALLOWED = new Set(`${CROCKFORD}OIL`);

/** The typed text without anything outside the alphabet, upper case, whole (not capped). */
function significant(text: string): string {
  let out = "";
  for (const char of text.toUpperCase()) if (ALLOWED.has(char)) out += char;
  return out;
}

function group(chars: string): string {
  return chars.match(/.{1,4}/g)?.join("-") ?? "";
}

/**
 * The recovery key as the field shows it: upper case, only the key's alphabet (plus `O`, `I`, `L`,
 * which the parser reads as `0`, `1`, `1`), at most 27 characters, a dash after every fourth.
 * Spaces, new lines and dashes in the input are dropped, so a paste in any shape regroups.
 */
export function groupRecoveryKey(text: string): string {
  return group(significant(text).slice(0, KEY_CHARS));
}

/** The index in `grouped` just after its `count`-th key character. */
function caretAfter(grouped: string, count: number): number {
  if (count <= 0) return 0;
  return count + Math.floor((count - 1) / GROUP);
}

/**
 * An edit of the field: `next` is what the input holds after the change and `caret` where its
 * caret is. Returns the grouped text and the caret to set, which stays after the same key
 * characters. Backspace right after a dash removes only the dash, which regrouping would put back,
 * so it removes the character before the dash instead.
 */
export function groupRecoveryKeyEdit(
  previous: string,
  next: string,
  caret: number,
): { text: string; caret: number } {
  let before = significant(next.slice(0, caret));
  let chars = significant(next);
  if (next.length < previous.length && chars === significant(previous) && before.length > 0) {
    before = before.slice(0, -1);
    chars = before + chars.slice(before.length + 1);
  }
  chars = chars.slice(0, KEY_CHARS);
  const text = group(chars);
  return { text, caret: caretAfter(text, Math.min(before.length, chars.length)) };
}

/** Whether the text holds all 27 characters of a key. */
export function isFullRecoveryKey(text: string): boolean {
  return significant(text).length === KEY_CHARS;
}
