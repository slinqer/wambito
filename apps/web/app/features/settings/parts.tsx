import { type ReactNode, useId } from "react";
import { useTranslations } from "use-intl";
import { cx } from "../../ui/cx.ts";

/** A card of settings named by its heading (so it is a landmark region). */
export function SettingsSection({
  title,
  lead,
  tone,
  children,
}: {
  title: string;
  lead?: string;
  /** "danger": deleting the account. */
  tone?: "danger";
  children: ReactNode;
}) {
  const id = useId();
  return (
    <section
      aria-labelledby={id}
      className={cx(
        "lk-hero flex min-w-0 flex-col gap-(--space-4)",
        tone === "danger" && "lk-danger-zone",
      )}
    >
      <div className="flex flex-col gap-(--space-1)">
        <h2
          id={id}
          className={cx(
            "m-0 font-display text-[20px] font-bold leading-tight",
            tone === "danger" ? "text-over" : "text-ink",
          )}
        >
          {title}
        </h2>
        {lead && <p className="m-0 text-[14px] text-ink-muted">{lead}</p>}
      </div>
      {children}
    </section>
  );
}

/**
 * In the demo, under a setting that can't work there (export, deleting the account, passkeys,
 * import): why its controls are off. With `local`, the same for a preview account's encrypted
 * vault (export, import, assistants: not available yet). Give the controls `aria-describedby={id}`.
 */
export function DemoOffNote({ id, local = false }: { id: string; local?: boolean }) {
  const t = useTranslations("settings");
  return (
    <p id={id} className="m-0 text-[14px] text-ink-muted">
      {t(local ? "local_off" : "demo_off")}
    </p>
  );
}

/** The name of one setting and, under it, a muted line on what it does. */
export function SettingLabel({
  label,
  hint,
  hintId,
}: {
  label: string;
  hint?: string;
  hintId?: string;
}) {
  return (
    <div className="flex flex-col gap-(--space-1)">
      <span className="text-[15px] font-bold text-ink">{label}</span>
      {hint && (
        <span id={hintId} className="text-[13px] text-ink-muted">
          {hint}
        </span>
      )}
    </div>
  );
}

const OPTION =
  "relative flex min-h-11 min-w-11 cursor-pointer items-center justify-center rounded-md border-2 border-stroke bg-surface-row px-(--space-2) text-center text-[14px] font-bold text-ink-muted shadow-edge-sm has-checked:border-brand-glow has-checked:text-ink has-checked:outline-3 has-checked:outline-gold has-checked:outline-offset-1 has-focus-visible:outline-3 has-focus-visible:outline-focus has-focus-visible:outline-offset-2 has-disabled:cursor-not-allowed has-disabled:opacity-60";

/**
 * One choice among a few (language, theme), as native radios in a fieldset named by `legend`:
 * the arrow keys move between them, and the chosen one is outlined in gold.
 */
export function Choices<T extends string>({
  legend,
  hint,
  name,
  value,
  options,
  onChange,
  disabled = false,
}: {
  legend: string;
  hint?: string;
  name: string;
  value: T;
  options: readonly { value: T; label: string; lang?: string }[];
  onChange(value: T): void;
  disabled?: boolean;
}) {
  const hintId = useId();
  return (
    <fieldset
      className="m-0 flex min-w-0 flex-col gap-(--space-2) border-0 p-0"
      disabled={disabled}
      aria-describedby={hint ? hintId : undefined}
    >
      <legend className="contents">
        <SettingLabel label={legend} />
      </legend>
      <div
        className="grid gap-(--space-2)"
        style={{ gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))` }}
      >
        {options.map((option) => (
          <label key={option.value} className={OPTION} lang={option.lang}>
            <input
              type="radio"
              name={name}
              value={option.value}
              checked={value === option.value}
              onChange={() => onChange(option.value)}
              className="absolute inset-0 m-0 cursor-pointer appearance-none opacity-0"
            />
            {option.label}
          </label>
        ))}
      </div>
      {hint && (
        <p id={hintId} className="m-0 text-[13px] text-ink-muted">
          {hint}
        </p>
      )}
    </fieldset>
  );
}

/** An on/off setting: the whole row is one switch, named by its label. */
export function SettingSwitch({
  label,
  hint,
  checked,
  onChange,
}: {
  label: string;
  hint?: string;
  checked: boolean;
  onChange(checked: boolean): void;
}) {
  const labelId = useId();
  const hintId = useId();
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-labelledby={labelId}
      aria-describedby={hint ? hintId : undefined}
      onClick={() => onChange(!checked)}
      className="lk-switch-row flex min-h-11 w-full items-center justify-between gap-(--space-3) rounded-md border-0 bg-transparent p-0 text-left"
    >
      <span className="flex flex-col gap-(--space-1)">
        <span id={labelId} className="text-[15px] font-bold text-ink">
          {label}
        </span>
        {hint && (
          <span id={hintId} className="text-[13px] font-normal text-ink-muted">
            {hint}
          </span>
        )}
      </span>
      <span className="lk-switch" aria-hidden="true">
        <span className="lk-switch-thumb" />
      </span>
    </button>
  );
}
