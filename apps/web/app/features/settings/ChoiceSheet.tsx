import { Sheet } from "../../ui/Sheet.tsx";
import { Choices } from "./parts.tsx";

/**
 * A sheet holding one of today's [Choices] (the language, the theme): picking applies at once and
 * the sheet closes. The row that opens it shows the current value.
 */
export function ChoiceSheet<T extends string>({
  open,
  onClose,
  title,
  hint,
  name,
  value,
  options,
  onChange,
}: {
  open: boolean;
  onClose(): void;
  /** Names the dialog and the group of choices. */
  title: string;
  hint?: string;
  name: string;
  value: T;
  options: readonly { value: T; label: string; lang?: string }[];
  onChange(value: T): void;
}) {
  return (
    <Sheet open={open} onClose={onClose} title={title}>
      <div className="pt-(--space-3)">
        <Choices
          legend={title}
          {...(hint ? { hint } : {})}
          name={name}
          value={value}
          options={options}
          onChange={(next) => {
            onChange(next);
            onClose();
          }}
        />
      </div>
    </Sheet>
  );
}
