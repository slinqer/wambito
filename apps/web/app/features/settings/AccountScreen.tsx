import { useTranslations } from "use-intl";
import { useApiMode } from "../../api/ApiProvider.tsx";
import { useMe } from "../../api/queries.ts";
import type { SignOutRequest } from "../home/use-sign-out.ts";
import { DeleteAccount } from "./DeleteAccount.tsx";
import { PasskeysSection } from "./PasskeysSection.tsx";
import type { PasskeysApi } from "./passkeys.ts";
import { SecuritySection } from "./SecuritySection.tsx";
import type { SecurityApi } from "./security.ts";
import type { ExportFormat } from "./use-export.ts";

/**
 * Cuenta y seguridad (`/app/settings/account`), the light version (spec 2026-11-22): the account's
 * email, a "Entrar con tu huella" group, for an encrypted account ("local" mode, `security` set) a
 * "Tus dispositivos" group and the recovery-key rows, and the delete row in red. A plain account
 * has only the passkeys and the delete row. Each long explanation lives in the sheet or flow its
 * row opens. In the demo the passkey and delete rows are off, with notes.
 */
export function AccountScreen({
  passkeys,
  security,
  signOut,
  onExport,
  exporting,
}: {
  passkeys: PasskeysApi;
  /** An encrypted account's keys; null for a plain account. */
  security: SecurityApi | null;
  signOut: SignOutRequest;
  onExport(format: ExportFormat): void;
  exporting: boolean;
}) {
  const t = useTranslations("settings");
  const me = useMe().data;
  if (!me) throw new Error("Settings renders inside AppShell, which waits for the profile");
  const mode = useApiMode();
  const demo = mode === "demo";
  const local = mode === "local";
  return (
    <>
      <p className="m-0 break-all text-[14px] text-ink-muted">
        {demo ? t("demo_viewing") : me.email}
      </p>
      <PasskeysSection
        passkeys={passkeys}
        timeZone={me.timezone}
        off={demo}
        vaultUserId={local ? me.id : undefined}
        security={security ?? undefined}
      />
      {security && (
        <SecuritySection security={security} passkeys={passkeys} timeZone={me.timezone} />
      )}
      <DeleteAccount
        email={me.email}
        {...(demo ? {} : { userId: me.id })}
        signOut={signOut}
        onExport={onExport}
        exporting={exporting}
        off={demo}
        canExport={!local}
      />
    </>
  );
}
