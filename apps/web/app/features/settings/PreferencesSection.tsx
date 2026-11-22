import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "use-intl";
import type { Translator } from "../../api/errors.ts";
import { queryKeys } from "../../api/queries.ts";
import { feedback, setSoundEnabled, soundEnabled } from "../../feedback/feedback.ts";
import { LOCALES, type Locale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { useTheme } from "../../theme/ThemeProvider.tsx";
import type { ThemePref } from "../../theme/theme-bootstrap.ts";
import { Icon } from "../../ui/Icon.tsx";
import { useToast } from "../../ui/Toast.tsx";
import type { Profile } from "../onboarding/onboarding-api.ts";
import { ChoiceSheet } from "./ChoiceSheet.tsx";
import { SettingsGroup, SettingsRow } from "./parts.tsx";
import { failureMessage, useSaveProfile } from "./use-profile.ts";

const THEMES: readonly ThemePref[] = ["auto", "night", "day"];

/**
 * "Apariencia" (language and theme, each a value row that opens a sheet with its choices) and
 * "Sonido y tacto" (the sound switch). The language applies at once (the catalogs switch, the URL
 * stays) and is saved on the profile; if saving fails it goes back, with a toast. Theme and sound
 * belong to this device. The sound's longer sentence is the switch's description.
 */
export function PreferencesSection() {
  const t = useTranslations("settings");
  const tRoot = useTranslations();
  const { pref, setPref } = useTheme();
  const [sound, setSound] = useState(soundEnabled);
  const [themeOpen, setThemeOpen] = useState(false);
  return (
    <>
      <SettingsGroup label={t("prefs.appearance")}>
        <LanguageRow />
        <SettingsRow
          icon={<Icon name="moon" size={20} />}
          title={tRoot("theme.label")}
          trailing={{ kind: "chevron", value: tRoot(`theme.${pref}`) }}
          onPress={() => setThemeOpen(true)}
        />
      </SettingsGroup>
      <ChoiceSheet
        open={themeOpen}
        onClose={() => setThemeOpen(false)}
        title={tRoot("theme.label")}
        hint={t("theme_hint")}
        name="theme"
        value={pref}
        options={THEMES.map((value) => ({ value, label: tRoot(`theme.${value}`) }))}
        onChange={setPref}
      />
      <SettingsGroup label={t("prefs.sound_touch")}>
        <SettingsRow
          icon={<Icon name="volume" size={20} />}
          title={t("prefs.sound_title")}
          line={t("prefs.sound_line")}
          description={t("sound_hint")}
          trailing={{
            kind: "switch",
            checked: sound,
            onChange: (on) => {
              setSoundEnabled(on);
              setSound(on);
              // A taste of it, when it comes back on.
              if (on) feedback("tap");
            },
          }}
        />
      </SettingsGroup>
    </>
  );
}

/** The language row: its own name as the value; the sheet applies the pick at once. */
function LanguageRow() {
  const tRoot = useTranslations();
  const { locale, setLocale } = useLocale();
  const qc = useQueryClient();
  const save = useSaveProfile();
  const toast = useToast();
  const [open, setOpen] = useState(false);

  const change = async (next: Locale) => {
    if (next === locale) return;
    // The shell follows the profile's language, so the cached profile changes with it.
    await qc.cancelQueries({ queryKey: queryKeys.me() });
    const before = qc.getQueryData<Profile>(queryKeys.me());
    if (before) qc.setQueryData(queryKeys.me(), { ...before, locale: next });
    setLocale(next);
    try {
      await save({ locale: next });
    } catch (problem) {
      if (before) qc.setQueryData(queryKeys.me(), before);
      setLocale(locale);
      toast.show({
        tone: "error",
        message: failureMessage(problem, tRoot as unknown as Translator),
      });
    }
  };

  return (
    <>
      <SettingsRow
        icon={<Icon name="globe" size={20} />}
        title={tRoot("language.label")}
        trailing={{
          kind: "chevron",
          value: <span lang={locale}>{tRoot(`language.${locale}`)}</span>,
        }}
        onPress={() => setOpen(true)}
      />
      <ChoiceSheet
        open={open}
        onClose={() => setOpen(false)}
        title={tRoot("language.label")}
        name="language"
        value={locale}
        // Each language is named in itself, and marked as such for screen readers.
        options={LOCALES.map((value) => ({
          value,
          label: tRoot(`language.${value}`),
          lang: value,
        }))}
        onChange={(next) => void change(next)}
      />
    </>
  );
}
