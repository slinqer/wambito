import { SettingsMenu } from "../features/settings/SettingsMenu.tsx";
import { screenMeta } from "../i18n/screen-meta.ts";

/** The same title as the layout's: a child route's `meta` replaces its parent's. */
export const meta = ({ location }: { location: { pathname: string; search: string } }) =>
  screenMeta("settings", location);

/** `/app/settings`: the menu of categories, with "Protect your data" above it when it applies. */
export default function Route() {
  return <SettingsMenu />;
}
