import { useMemo } from "react";
import { redirect } from "react-router";
import { createTranslator } from "use-intl/core";
import { accountGate } from "../auth/encryption.ts";
import { requireSession } from "../auth/session.ts";
import { Consent } from "../features/assistants/Consent.tsx";
import { createConsentApi, liveConsentApi } from "../features/assistants/consent-api.ts";
import type { ConsentKeys } from "../features/assistants/consent-model.ts";
import type { UnlockMeans } from "../features/vault/vault-gate.ts";
import { CATALOGS } from "../i18n/catalog.ts";
import { hasPasskeyWrap, loadLocalKeys, withDataKeyFrom } from "../local/keys.ts";
import { evaluatePrf } from "../local/prf.ts";
import { passkeyGaveNoPrf } from "../local/unlock-hint.ts";
import type { Route } from "./+types/oauth.consent";

/** The query carries the assistant's state and a signature: this page never sends a referrer. */
export const meta = () => {
  const t = createTranslator({ locale: "es", messages: CATALOGS.es, namespace: "consent" });
  return [
    { title: t("meta_title") },
    { name: "robots", content: "noindex" },
    { name: "referrer", content: "no-referrer" },
  ];
};

/**
 * Signed in only: a visitor who is not goes to sign-in and comes back to this very URL, signed
 * query and all. A failed session check throws to the error boundary. An encrypted account
 * (`GET /v1/me` `encryption: "preview"`) gives its assistant a key: `device` when this browser
 * holds its vault (DK from the device wrap, no touch), else the page asks for a passkey or the
 * recovery key. While the account's move to end-to-end encryption runs, the page sends it to the
 * flow (`/app`): an assistant connected then would be revoked by the move's finish. One the move
 * is only open to connects as a plain account (the move's finish revokes it too, later).
 */
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const url = new URL(request.url);
  const user = await requireSession(`${url.pathname}${url.search}`);
  const guest = user.isAnonymous === true;
  const { vault: profile, migration } = await accountGate();
  if (migration?.migration === "in_progress") throw redirect("/app");
  if (!profile) return { guest, encrypted: null };
  let device = false;
  try {
    device = (await loadLocalKeys(profile.id)) !== null;
  } catch {
    // no IndexedDB here: the passkey or the recovery key
  }
  return {
    guest,
    encrypted: { userId: profile.id, device, means: await meansOf(profile.id, device) },
  };
}

/**
 * What can open the data here, for the unlock step's layout (as the vault gate reads it): the
 * device's no-PRF hint, and whether the account has a passkey wrap (true when the wraps cannot be
 * read). Not asked when this browser holds the vault: no unlock step then.
 */
async function meansOf(userId: string, device: boolean): Promise<UnlockMeans> {
  if (device) return { noPrfHere: false, passkeyWrap: true };
  let passkeyWrap = true;
  try {
    passkeyWrap = await hasPasskeyWrap({ userId });
  } catch {
    passkeyWrap = true;
  }
  return { noPrfHere: passkeyGaveNoPrf(userId), passkeyWrap };
}

/** While the session is checked: the screen's background, nothing to read yet. */
export function HydrateFallback() {
  return <div className="lk-screen min-h-dvh" />;
}

/** `/oauth/consent?client_id&scope&…&sig`: an assistant asks to connect (spec §6.1). */
export default function ConsentRoute({ loaderData }: Route.ComponentProps) {
  const { guest, encrypted } = loaderData;
  const userId = encrypted?.userId;
  const device = encrypted?.device ?? false;
  const means = encrypted?.means;
  const api = useMemo(
    () => (userId ? createConsentApi(undefined, { userId }) : liveConsentApi),
    [userId],
  );
  const keys = useMemo<ConsentKeys | undefined>(
    () =>
      userId
        ? {
            userId,
            device,
            open: (source, fn) => withDataKeyFrom({ userId }, source, fn),
            touchPasskey: () => evaluatePrf(),
            ...(means ? { means } : {}),
          }
        : undefined,
    [userId, device, means],
  );
  return <Consent api={api} guest={guest} {...(keys ? { keys } : {})} />;
}
