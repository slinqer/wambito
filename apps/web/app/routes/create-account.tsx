import { redirectIfSignedIn } from "../auth/session.ts";
import { liveSignInAuth } from "../features/sign-in/auth.ts";
import { signInMeta } from "../features/sign-in/meta.ts";
import { SignIn } from "../features/sign-in/SignIn.tsx";
import type { Route } from "./+types/create-account";

export const meta = ({ location }: Route.MetaArgs) => signInMeta("sign_in.create", location.search);

/** Someone already signed in goes on to `next`, the app, or onboarding, as on `/sign-in`. */
export const clientLoader = ({ request }: Route.ClientLoaderArgs) =>
  redirectIfSignedIn({ request });

/** While the session is checked: the screen's background, nothing to read yet. */
export function HydrateFallback() {
  return <div className="lk-screen min-h-dvh" />;
}

/** `/create-account` (the landing's "Create account"): the email code form, no QR (ruling 3). */
export default function CreateAccountRoute() {
  return <SignIn auth={liveSignInAuth} mode="create" />;
}
