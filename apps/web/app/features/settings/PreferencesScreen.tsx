import type { Profile } from "../onboarding/onboarding-api.ts";
import { PreferencesSection } from "./PreferencesSection.tsx";
import { TimeAndMoneySection } from "./TimeAndMoneySection.tsx";

/**
 * Preferencias (`/app/settings/preferences`), the light version (spec 2026-11-22): "Apariencia"
 * (language, theme), "Sonido y tacto" (sound) and "Hora y moneda" (time zone, currency), one row
 * each; the language, theme, time zone and currency open a sheet with their choices.
 */
export function PreferencesScreen({ me }: { me: Profile }) {
  return (
    <>
      <PreferencesSection />
      <TimeAndMoneySection me={me} />
    </>
  );
}
