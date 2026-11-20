import { type Ref, useLayoutEffect, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import { cx } from "../../ui/cx.ts";
import { groupRecoveryKey, groupRecoveryKeyEdit } from "./recovery-key-input.ts";

export interface RecoveryKeyFieldProps {
  id: string;
  /** The grouped text; the parent keeps it in state. */
  value: string;
  /** Called with the grouped text after every change, a paste included. */
  onChange(text: string): void;
  invalid?: boolean;
  /** The id of the error that describes the field. */
  describedBy?: string | undefined;
  disabled?: boolean;
  /** Read only while busy: the field keeps focus. */
  readOnly?: boolean;
  inputRef?: Ref<HTMLInputElement>;
  name?: string;
}

/**
 * The recovery key's input: shows it in groups of four while the person types, regroups a paste in
 * any shape and keeps the caret after the same characters. A "Paste" button reads the clipboard
 * where the browser allows it; a refused read does nothing.
 */
export function RecoveryKeyField({
  id,
  value,
  onChange,
  invalid,
  describedBy,
  disabled,
  readOnly,
  inputRef,
  name = "recovery-key",
}: RecoveryKeyFieldProps) {
  const t = useTranslations("vault.unlock");
  const input = useRef<HTMLInputElement | null>(null);
  const caret = useRef<number | null>(null);
  const [canPaste] = useState(
    () => typeof navigator !== "undefined" && typeof navigator.clipboard?.readText === "function",
  );

  // after React writes the grouped value the browser moves the caret to the end: put it back
  useLayoutEffect(() => {
    if (caret.current !== null && input.current) {
      input.current.setSelectionRange(caret.current, caret.current);
    }
    caret.current = null;
  }, [value]);

  function setRefs(node: HTMLInputElement | null) {
    input.current = node;
    if (typeof inputRef === "function") inputRef(node);
    else if (inputRef) inputRef.current = node;
  }

  async function paste() {
    try {
      const text = await navigator.clipboard.readText();
      caret.current = null;
      onChange(groupRecoveryKey(text));
      input.current?.focus();
    } catch {
      // refused or empty: nothing happens
    }
  }

  return (
    <div className={cx("lk-input min-h-11", invalid && "border-over")}>
      <input
        ref={setRefs}
        id={id}
        name={name}
        type="text"
        autoComplete="off"
        autoCapitalize="characters"
        autoCorrect="off"
        spellCheck={false}
        translate="no"
        placeholder={t("placeholder")}
        value={value}
        disabled={disabled}
        readOnly={readOnly}
        onChange={(event) => {
          const edit = groupRecoveryKeyEdit(
            value,
            event.target.value,
            event.target.selectionStart ?? event.target.value.length,
          );
          caret.current = edit.caret;
          onChange(edit.text);
          // the grouped text may equal the old one (a rejected character): React skips the effect
          if (edit.text === value) {
            event.target.value = edit.text;
            event.target.setSelectionRange(edit.caret, edit.caret);
          }
        }}
        aria-invalid={invalid || undefined}
        aria-describedby={describedBy}
        className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-mono text-[16px] text-ink uppercase outline-none placeholder:font-normal placeholder:text-ink-muted"
      />
      {canPaste && (
        <button
          type="button"
          disabled={disabled || readOnly}
          onClick={() => void paste()}
          className="min-h-9 shrink-0 cursor-pointer border-0 bg-transparent px-(--space-2) font-semibold text-[14px] text-ink-muted"
        >
          {t("paste")}
        </button>
      )}
    </div>
  );
}
