import { index, layout, type RouteConfig, route } from "@react-router/dev/routes";
import { readBuildEnv } from "./site/build-env.ts";
import { isLandingOnly } from "./site/origin.ts";

const landingOnly = isLandingOnly(readBuildEnv().landingOnly);

export default [
  // The landing page, prerendered per language (react-router.config.ts).
  index("routes/_index.tsx"),
  route("en", "routes/en._index.tsx"),
  route("it", "routes/it._index.tsx"),
  route("pt", "routes/pt._index.tsx"),
  // The public roadmap, prerendered per language like the landing (react-router.config.ts).
  route("roadmap", "routes/roadmap.tsx"),
  route("en/roadmap", "routes/en.roadmap.tsx"),
  route("it/roadmap", "routes/it.roadmap.tsx"),
  route("pt/roadmap", "routes/pt.roadmap.tsx"),
  // The privacy policy and the account deletion page, prerendered per language too.
  route("privacy", "routes/privacy.tsx"),
  route("en/privacy", "routes/en.privacy.tsx"),
  route("it/privacy", "routes/it.privacy.tsx"),
  route("pt/privacy", "routes/pt.privacy.tsx"),
  route("delete-account", "routes/delete-account.tsx"),
  route("en/delete-account", "routes/en.delete-account.tsx"),
  route("it/delete-account", "routes/it.delete-account.tsx"),
  route("pt/delete-account", "routes/pt.delete-account.tsx"),
  // How automatic capture works, prerendered per language too.
  route("automatic-capture", "routes/automatic-capture.tsx"),
  route("en/automatic-capture", "routes/en.automatic-capture.tsx"),
  route("it/automatic-capture", "routes/it.automatic-capture.tsx"),
  route("pt/automatic-capture", "routes/pt.automatic-capture.tsx"),
  // Every screen of the app (sign-in, welcome, /app/*) nests under this layout, which holds the
  // API client, its cache and the toasts. The landing stays outside it, so visitors do not download
  // that code. The demo (/demo/*) has its own layout with a demo ApiProvider, beside this one.
  // The landing-only release has no app, so the layout (and its code and sounds) is left out, and
  // any other path is a prerendered 404 (react-router.config.ts); its "Pruébalo sin cuenta" opens
  // the demo on the app's origin.
  ...(landingOnly
    ? [route("*", "routes/not-found.tsx")]
    : [
        layout("routes/app-layout.tsx", [
          route("sign-in", "routes/sign-in.tsx"),
          route("auth/verify", "routes/auth.verify.tsx"),
          // The link of an email change (admin panel spec §5.2): works signed in or not.
          route("confirm-email", "routes/confirm-email.tsx"),
          // After an email sign-in: "¿Entrar con tu huella la próxima vez?", once per user per device.
          route("passkey-offer", "routes/passkey-offer.tsx"),
          route("welcome/:step?", "routes/welcome.tsx"),
          // An assistant (Claude, ChatGPT) asks to connect: Better Auth's consentPage (spec §6.1).
          route("oauth/consent", "routes/oauth.consent.tsx"),
          // The sign-in link for that consent: the same page as /auth/verify, on a path the Android
          // app does not claim, so the link stays in the browser the assistant opened.
          route("oauth/verify", "routes/auth.verify.tsx", { id: "oauth-verify" }),
          // The signed-in app: its shell (bottom bar or sidebar, the add sheet) and home.
          route("app", "routes/app.tsx", [
            index("routes/app._index.tsx"),
            // The import on its own, after onboarding (home's "Trae tu historial").
            route("import", "routes/app.import.tsx"),
            // The old categories page: home's Categorías tab now.
            route("categories", "routes/app.categories._index.tsx"),
            route("categories/:id", "routes/app.categories.$id.tsx"),
            route("recurring", "routes/app.recurring.tsx"),
            route("insights", "routes/app.insights.tsx"),
            route("search", "routes/app.search.tsx"),
            route("settings", "routes/app.settings.tsx"),
          ]),
        ]),
        // The admin panel (admin panel spec §3): its own layout, with the app's API client and its
        // own Spanish/English messages; signed in, and the API decides who is an admin (anyone
        // else sees the not-found page). Its code loads only on /admin, and the landing-only
        // release leaves it out with the app.
        route("admin", "routes/admin.tsx", [
          index("routes/admin._index.tsx"),
          route("users/:id", "routes/admin.users.$id.tsx"),
        ]),
        // Try before signing up (spec §2.6b): the same screens as /app (the same route modules,
        // under their own ids), as the made-up "Valentina (demo)", on a backend in the page. No
        // import: settings turns it off in the demo.
        route("demo", "routes/demo.tsx", [
          index("routes/app._index.tsx", { id: "demo-home" }),
          route("categories", "routes/app.categories._index.tsx", { id: "demo-categories" }),
          route("categories/:id", "routes/app.categories.$id.tsx", { id: "demo-category" }),
          route("recurring", "routes/app.recurring.tsx", { id: "demo-recurring" }),
          route("insights", "routes/app.insights.tsx", { id: "demo-insights" }),
          route("search", "routes/app.search.tsx", { id: "demo-search" }),
          route("settings", "routes/app.settings.tsx", { id: "demo-settings" }),
        ]),
      ]),
] satisfies RouteConfig;
