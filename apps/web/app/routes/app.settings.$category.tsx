import { useParams } from "react-router";
import { SettingsCategoryScreen } from "../features/settings/Settings.tsx";
import { screenMeta } from "../i18n/screen-meta.ts";

/** The same title as the layout's: a child route's `meta` replaces its parent's. */
export const meta = ({ location }: { location: { pathname: string; search: string } }) =>
  screenMeta("settings", location);

/** `/app/settings/:category`: one category's page; an unknown name shows the page's not-found. */
export default function Route() {
  const { category = "" } = useParams();
  return <SettingsCategoryScreen category={category} />;
}
