import { Outlet } from "react-router";
import { screenMeta } from "../i18n/screen-meta.ts";

/** Spanish in the app; in the demo (which reuses this module), the demo's language. */
export const meta = ({ location }: { location: { pathname: string; search: string } }) =>
  screenMeta("settings", location);

/**
 * `/app/settings`: the layout of Settings. Its index is the menu of categories and each category
 * is its own page (`app.settings._index.tsx`, `app.settings.$category.tsx`). Signed in and
 * onboarded: the `/app` layout checks it.
 */
export default function Route() {
  return <Outlet />;
}
