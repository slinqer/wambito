import { useTranslations } from "use-intl";
import { PressButton } from "../../ui/PressButton.tsx";
import { PressLink } from "../../ui/PressLink.tsx";
import { STORE_LINKS, type StoreLinks } from "../landing/links.ts";
import { ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";

export interface InstallAppProps {
  /** The person goes on to the web app. */
  onContinue(): void;
  /** Where each way to get the phone app lives; a store whose link is null shows no button. */
  links?: StoreLinks;
}

/**
 * Offered once, right after an account is set up in the browser: the phone is where Wambito lives.
 * The Android APK is always there; each store shows only once its link is set (`links.ts`).
 */
export function InstallApp({ onContinue, links = STORE_LINKS }: InstallAppProps) {
  const t = useTranslations("vault.install");
  const stores = [
    { href: links.play, label: t("play") },
    { href: links.fdroid, label: t("fdroid") },
    { href: links.appStore, label: t("app_store") },
  ];
  return (
    <SignInScreen>
      <ScreenTitle>{t("title")}</ScreenTitle>
      <p className="text-center text-ink-muted">{t("lead")}</p>
      {links.apk && (
        <PressLink to={links.apk} className="w-full">
          {t("android")}
        </PressLink>
      )}
      {stores.map(
        (store) =>
          store.href && (
            <PressLink key={store.label} to={store.href} variant="secondary" className="w-full">
              {store.label}
            </PressLink>
          ),
      )}
      {links.release && (
        <a
          href={links.release}
          className="inline-flex min-h-11 items-center text-ink-muted underline"
        >
          {t("release")}
        </a>
      )}
      <PressButton variant="ghost" className="w-full" onClick={onContinue}>
        {t("continue")}
      </PressButton>
    </SignInScreen>
  );
}
