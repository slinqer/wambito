import { Search } from "../features/search/Search.tsx";
import { screenMeta } from "../i18n/screen-meta.ts";

/** Spanish in the app; in the demo (which reuses this module), the demo's language. */
export const meta = ({ location }: { location: { pathname: string; search: string } }) =>
  screenMeta("search", location);

/**
 * `/app/search`: movements across every month by name, note, kind, category and status. Signed in
 * and onboarded: the `/app` layout checks it.
 */
export default function Route() {
  return <Search />;
}
