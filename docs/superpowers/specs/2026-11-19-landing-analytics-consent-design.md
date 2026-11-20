# Landing analytics with consent (PostHog)

Date: 2026-11-19. Status: approved.

## Why

We want to see how people use the landing (wambito.com): where they stop reading, what they
click, why they don't install. PostHog gives page views, clicks and session recordings. Wambito
sells privacy, so this has to respect EU rules (ePrivacy + GDPR) without bending them: no consent,
no tracking. When someone says no, or their browser already says no, we don't track them, ever.

## Goals

- PostHog (EU cloud) on the public pages only: the landing, roadmap, privacy, delete-account and
  automatic-capture pages, in es/en/it/pt.
- A consent banner in Wambito's style. Accept and Decline are equally easy (same size, same row,
  one click each).
- Nothing from PostHog loads (no script, no cookie, no request) before the person clicks Accept.
- Global Privacy Control or Do Not Track on: no banner, no tracking, treated as a refusal.
- The person can change their mind at any time from a footer link.
- The privacy policy says all of this honestly, in the four languages.

## Non-goals

- Analytics inside the app (`/app/*`), the demo (`/demo/*`), sign-in, consent or admin. Nothing
  from PostHog runs on the app origin. App analytics, if we ever want them, get their own spec
  and their own consent.
- The phone app.
- A full consent-management platform (categories, vendor lists). There is one purpose: analytics.

## Anti-goals (a failure even if it works)

- Any PostHog request or cookie before Accept, including "anonymous" or "cookieless" counting.
- A banner that nudges: a big Accept and a grey Decline, a pre-ticked box, or "by continuing you
  accept".
- Financial data, or anything typed into a field, inside a recording.
- Self-hosters, dev builds or e2e runs sending data to our PostHog project.

## Approaches

1. **Wait for Accept (chosen).** The script loads only after Accept; Decline or GPC/DNT means it
   never loads. Less data (we see only those who accept), but clean and easy to defend.
2. Strict opt-in plus PostHog's cookieless counting for those who decline. More complete numbers,
   but it contradicts "no means no", and its legal standing in the EU is debated. Rejected.
3. Load by default and delete on Decline. Not lawful: consent must come before the cookie and the
   recording, and the browser can't delete a person server side without a secret key. Rejected.

## Design

### Build switch

- `VITE_POSTHOG_KEY` (the project's public key, which is not a secret) and `VITE_POSTHOG_HOST`
  (default `https://eu.i.posthog.com`), read like the other `VITE_*` build switches
  (`app/site/build-env.ts`).
- No key: no banner, no footer link, no PostHog code in the page. This covers self-hosters, dev
  and every existing e2e run.
- CI's `deploy-landing` build sets the key (a GitHub Actions variable). The VPS app build does
  not, since it redirects its landing paths to wambito.com anyway.

### The decision

- Kept in `localStorage` under `wambito.consent.analytics`, as
  `{ "v": 1, "choice": "granted" | "denied", "at": "<ISO date>" }`. Storing the choice itself is
  strictly necessary, so it needs no consent.
- It expires after 6 months, and then we ask again (our call; the CNIL's guidance for
  refusals). A stored `v` lower than the current one also asks again (for when the policy
  changes).
- GPC (`navigator.globalPrivacyControl === true`) or DNT (`navigator.doNotTrack === "1"`) wins
  over everything, including a stored "granted": the page acts as "denied" and shows no banner.
- A pure model module (`consent-model.ts`-style, no React) decides between `ask`, `granted` and
  `denied` from the stored value, the browser signals and today's date. It is unit-tested first.

### Loading PostHog

- `posthog-js` comes in through a dynamic `import()`, so it sits in its own chunk that the browser
  downloads only after Accept, or on a later visit whose stored choice is "granted".
- Init options: `api_host` from the switch, `person_profiles: "identified_only"` (no one is ever
  identified, so no person profiles), `respect_dnt: true` (belt and braces), session recording
  with `maskAllInputs: true` and `maskTextSelector` on anything showing money in the landing
  demo, `capture_pageview: "history_change"`, `persistence: "localStorage+cookie"`, and
  `cross_subdomain_cookie: false`, so `ph_*` cookies never reach `app.wambito.com`.
- In the PostHog project (by hand, written in `docs/deploy/landing.md`): EU region, "discard
  client IP data" on, recordings kept for the shortest retention the plan offers, recordings
  limited to the `wambito.com` domain.

### Withdrawing

- The footer gets a "Cookie preferences" link (in every language) beside Privacy, only when the
  key is set. It opens the banner again, with the current choice shown.
- Going from granted to denied: `opt_out_capturing()`, stop the recording, `reset()`, and delete
  the `ph_*` cookies and `localStorage` keys. Nothing is sent after that.
- Data PostHog already holds is deleted on request by email (privacy@wambito.com), as the
  policy says; the browser can't do it (it needs a personal API key).
- With GPC/DNT on, the link opens a short note ("Your browser asked not to be tracked, so we
  don't") instead of the buttons.

### The banner

A card fixed at the bottom of the page, not a wall: the page stays readable and clickable behind
it. It uses the landing's tokens and type (Fredoka titles, Nunito text, `lk-landing-*` classes),
light and dark, with no Wambi (it would compete with the hero).

```
┌──────────────────────────────────────────────────────────────┐
│  ¿Nos dejas ver cómo usas esta página?                       │
│  Con PostHog vemos qué lees y dónde haces clic, y grabamos   │
│  la visita sin lo que escribes. Solo en wambito.com, nunca   │
│  en la app ni con tus finanzas. Más en Privacidad.           │
│                                                              │
│        [ No, gracias ]          [ Sí, acepto ]               │
└──────────────────────────────────────────────────────────────┘
```

- Both buttons are the same component and size. Decline is first in the reading order.
- It's a `role="region"` with a label, not a modal: no focus trap, reachable by keyboard, and it
  passes the existing axe check (`e2e/a11y.spec.ts`).
- Mounted from `Footer` (which every public page renders), so the app and the demo never get it.
- It shows after hydration only. The prerendered HTML has no banner, so nothing flashes for those
  who already chose.

### The privacy policy (`legal.privacy.*`, es/en/it/pt)

- `not_done` is rewritten: no ads, no selling or sharing your data, and nothing from inside the
  app (your finances are encrypted end to end) ever goes to analytics.
- A new `analytics` section, after `storage`: on wambito.com only, with your permission, PostHog
  (EU servers) receives the pages you visit, your clicks and a recording of the visit with what
  you type hidden; it does not keep your IP; how long it's kept; how to withdraw (the footer link)
  and how to ask for deletion (the email). GPC/DNT is respected.
- The controller stays Slinqer S.A.S. (section `controller`). The section names PostHog Inc. as
  a US company that processes the data on its EU servers for us, under its data processing
  agreement (DPA) with standard contractual clauses.
- The retention numbers in the section are the real ones from the PostHog project; the copy
  never says "the shortest" without a number.
- `PRIVACY_SECTIONS` gets `analytics`, and the policy's date moves to the release date.

### Rollout

- The code can merge with `VITE_POSTHOG_KEY` unset: nothing shows and nothing loads, so merging
  (which deploys) changes nothing for visitors.
- No PostHog project exists yet. The founder creates the account and an EU project; the plan
  lists the project settings to apply and where to read the real retention numbers, which go
  into the policy copy before the key is set.
- Tracking goes live only when the GitHub variable is set. That happens after the PostHog
  project is set up (EU, IP discarded, retention), the DPA is accepted and the policy copy is
  final.

### Tests (written first)

- Unit: the consent model (each case above, including expiry, the version bump and GPC beating a
  stored "granted"); the withdraw step clears `ph_*` storage.
- Component (Vitest + Testing Library): banner equal buttons, the decision stored, the footer
  link reopens it, nothing rendered without the key.
- e2e on a built landing with a fake key and PostHog's host routed by Playwright: no request to
  that host before Accept; a request after Accept; none after Decline, or on a reload after
  Decline; none with GPC set; none after withdrawing. The existing landing-only runs (no key)
  must show no banner.
- Storybook stories for the banner (ask, GPC note), light and dark.

## Constraints

- The landing is static assets on a Cloudflare Worker, with no Worker code. So there is no
  PostHog reverse proxy; the browser talks to `eu.i.posthog.com` directly. Ad blockers will block
  some of it, and we accept that.
- No CSP today, so there's nothing to widen. Add one later, and `eu.i.posthog.com` goes in it.
- Everything in English in the repo. Copy in four languages through the site catalogs.
- `apps/web/AGENTS.md` and `docs/deploy/landing.md` are updated (the switch, the PostHog project
  settings).

## Left to the builder

- Exact copy in en/it/pt, matching the tone of the existing policy.
- Which landing elements get `maskTextSelector` (the money demos).
- Where the GitHub variable is wired in `ci.yml`.
- Figma: the banner is not a new screen or route, so the screens map doesn't change. Mention it
  in the PR anyway.
