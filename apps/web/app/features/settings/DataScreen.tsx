import { useId, useState } from "react";
import { useTranslations } from "use-intl";
import { useApiMode } from "../../api/ApiProvider.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import { useAppPath } from "../home/app-path.ts";
import { DemoOffNote, SettingsGroup, SettingsRow } from "./parts.tsx";
import type { ExportFormat } from "./use-export.ts";

/**
 * Tus datos (`/app/settings/data`), the light version (spec 2026-11-22): "Importar movimientos"
 * (a chevron to the import page) and "Descargar tus datos" (opens today's export choices, JSON and
 * CSV, in a sheet). In the demo both are off, with the note under the group; a preview account
 * (`local` mode) shows "Próximamente" on import and has the export off, with its own note. The
 * import's longer sentence is the row's description.
 */
export function DataScreen({
  onExport,
  exporting,
}: {
  onExport(format: ExportFormat): Promise<void> | void;
  /** The format being prepared, or null. */
  exporting: ExportFormat | null;
}) {
  const t = useTranslations("settings.data");
  const appPath = useAppPath();
  const mode = useApiMode();
  const demo = mode === "demo";
  const local = mode === "local";
  const off = demo || local;
  const noteId = useId();
  const [open, setOpen] = useState(false);

  const run = async (format: ExportFormat) => {
    await onExport(format);
    setOpen(false);
  };

  return (
    <>
      <SettingsGroup>
        <SettingsRow
          icon={<Icon name="upload" size={20} />}
          title={t("import_row")}
          line={t("import_row_line")}
          description={t("import_lead")}
          trailing={
            local ? { kind: "chip", text: t("soon") } : off ? { kind: "none" } : { kind: "chevron" }
          }
          {...(off ? {} : { href: appPath("/import") })}
        />
        <SettingsRow
          icon={<Icon name="download" size={20} />}
          title={t("export_row")}
          line={t("export_row_line")}
          trailing={off ? { kind: "none" } : { kind: "chevron" }}
          {...(off ? {} : { onPress: () => setOpen(true) })}
        />
      </SettingsGroup>
      {off && <DemoOffNote id={noteId} local={local} />}
      <Sheet open={open} onClose={() => setOpen(false)} title={t("export_title")}>
        <div className="flex flex-col gap-(--space-3) pt-(--space-3)">
          <p className="m-0 text-[14px] text-ink-muted">{t("export_lead")}</p>
          <div className="flex flex-wrap gap-(--space-2)">
            {(["json", "csv"] as const).map((format) => (
              <PressButton
                key={format}
                variant="secondary"
                disabled={exporting !== null}
                aria-busy={exporting === format || undefined}
                onClick={() => void run(format)}
              >
                {t(format === "json" ? "export_json" : "export_csv")}
              </PressButton>
            ))}
          </div>
        </div>
      </Sheet>
    </>
  );
}
