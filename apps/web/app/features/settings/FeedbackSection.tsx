import { useState } from "react";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { PressLink } from "../../ui/PressLink.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import { APP_VERSION, FEEDBACK_EMAIL, feedbackMailto } from "./feedback.ts";
import { SettingsGroup, SettingsRow } from "./parts.tsx";

/**
 * "Comentarios e ideas": a row that opens a sheet with today's form, a button that opens the
 * person's email app with a message to the founder ready to write. The subject says what it is, in
 * the person's language, and the body carries only the version and the language; nothing else of
 * the account goes in it. A browser with no email app does nothing with a `mailto:` link, so the
 * address is also written out under the button.
 */
export function FeedbackSection() {
  const t = useTranslations("settings.feedback");
  const { locale } = useLocale();
  const [open, setOpen] = useState(false);
  const link = feedbackMailto({
    subject: t("mail_subject"),
    body: `\n\n${t("mail_body", { version: APP_VERSION, language: locale })}`,
  });
  return (
    <>
      <SettingsGroup>
        <SettingsRow
          icon={<Icon name="chat" size={20} />}
          title={t("title")}
          line={t("row_line")}
          trailing={{ kind: "chevron" }}
          onPress={() => setOpen(true)}
        />
      </SettingsGroup>
      <Sheet open={open} onClose={() => setOpen(false)} title={t("title")}>
        <div className="flex flex-col gap-(--space-3) pt-(--space-3)">
          <p className="m-0 text-[15px] text-ink">{t("lead")}</p>
          <PressLink to={link} variant="secondary" className="self-start">
            {t("action")}
          </PressLink>
          <p className="m-0 text-[14px] text-ink-muted">
            {t("address", { email: FEEDBACK_EMAIL })}
          </p>
        </div>
      </Sheet>
    </>
  );
}
