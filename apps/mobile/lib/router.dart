import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/session.dart';
import 'entry/email_screen.dart';
import 'entry/passkey_offer_page.dart';
import 'entry/entry_screen.dart';
import 'entry/verify_link_screen.dart';
import 'budgets/category_detail_screen.dart';
import 'debug/prf_probe_screen.dart';
import 'home/home_screen.dart';
import 'import/import_screen.dart';
import 'insights/insights_screen.dart';
import 'progress/progress_screen.dart';
import 'recurring/recurring_screen.dart';
import 'review/review_screen.dart';
import 'search/search_screen.dart';
import 'settings/about_screen.dart';
import 'settings/home_actions.dart';
import 'settings/settings_screen.dart';
import 'vault/encryption_mode.dart';
import 'vault/vault_gate.dart';
import 'vault/vault_providers.dart';
import 'vault/vault_screen.dart';
import 'welcome/welcome_screen.dart';

const _offerPath = '/entry/passkey-offer';

/// Where a person with the offer pending is sent from: the sign-in screens and home.
const _offerFirst = {'/', '/loading', '/entry', '/entry/email'};

/// Where the signed-in account's vault stands for the router (the gate of lib/vault):
/// - `open`: the account is `plain`, or its vault is open: every screen is for it;
/// - `locked`: a `preview` account whose vault is not open, or one whose mode nobody could tell
///   (an offline first start): `/unlock` is all it gets, and says what to do;
/// - `loading`: the mode of the account is still being learned: the loading route, so a screen
///   never treats a possibly-`preview` account as `plain`.
enum VaultRoute { open, locked, loading }

/// The vault's standing for the session signed in now. Reads [currentVaultAccountProvider], never
/// the mode provider's value (which keeps the previous session's while it loads): `vaultAccountProvider`
/// only decides between "still asking" and "could not ask" once the account is unknown.
VaultRoute vaultRouteOf(Ref ref) {
  if (ref.read(sessionProvider).status != SessionStatus.signedIn) return VaultRoute.open;
  final account = ref.read(currentVaultAccountProvider);
  if (account == null) {
    final asked = ref.read(vaultAccountProvider);
    return asked.hasError && !asked.isLoading ? VaultRoute.locked : VaultRoute.loading;
  }
  if (account.mode == EncryptionMode.plain) return VaultRoute.open;
  return ref.read(vaultGateStateProvider) is Ready ? VaultRoute.open : VaultRoute.locked;
}

/// Where the session sends a [location], or null to stay:
/// - the magic link (`/auth/verify`) always opens: it decides for itself, guests included;
/// - while the stored session is read, a blank screen;
/// - signed out, only the entry screens;
/// - signed in, never the first-run screen, and the email screen and "Guarda tu progreso" only for
///   a guest (to save their progress, or to sign in as another account after a warning);
/// - signed in with the welcome to do (an account with no `onboardingCompletedAt`), the welcome from
///   every other screen, as the web's `requireOnboarded`; and nothing else but the welcome, which
///   an account that finished it, and a guest, never see;
/// - right after an email sign-in that is due the passkey offer, the offer comes first, wherever the
///   person was going from the sign-in screens; its address is for that moment only;
/// - signed in with a `preview` account (the [vault]): every screen but the magic link, the entry
///   screens and the debug ones goes to `/unlock` until its vault is open, and `/unlock` goes home
///   once it is; while the mode is unknown, the loading route.
String? sessionRedirect(SessionState session, Uri location, {VaultRoute vault = VaultRoute.open}) {
  final path = location.path;
  if (path == '/auth/verify') return null;
  switch (session.status) {
    case SessionStatus.loading:
      return path == '/loading' ? null : '/loading';
    case SessionStatus.signedOut:
      return path == '/entry' || path == '/entry/email' ? null : '/entry';
    case SessionStatus.signedIn:
      final vaultOnly =
          !(path == '/entry' || path.startsWith('/entry/') || path.startsWith('/debug/'));
      if (vaultOnly) {
        switch (vault) {
          case VaultRoute.loading:
            return path == '/loading' ? null : '/loading';
          case VaultRoute.locked:
            return path == '/unlock' ? null : '/unlock';
          case VaultRoute.open:
            if (path == '/unlock') return '/';
        }
      }
      if (session.offerPasskeyFor != null && _offerFirst.contains(path)) return _offerPath;
      if (path == _offerPath && session.offerPasskeyFor == null) {
        return session.onboardingPending ? '/welcome' : '/';
      }
      final inWelcome = path == '/welcome' || path.startsWith('/welcome/');
      if (session.onboardingPending) {
        // The passkey offer, while it is due, comes before the welcome (the web's offer leads on to
        // the page the person was going to).
        if (path == _offerPath) return null;
        return inWelcome ? null : '/welcome';
      }
      if (inWelcome) return '/';
      if (path == '/loading' || path == '/entry') return '/';
      if ((path == '/entry/email' || path == '/progress') && !session.isGuest) return '/';
      return null;
  }
}

/// The app's routes. Screens join here as they are built.
final routerProvider = Provider<GoRouter>((ref) {
  final session = ValueNotifier<SessionState>(ref.read(sessionProvider));
  // The vault's standing, with the session: either changing sends the redirect round again.
  final vault = ValueNotifier<VaultRoute>(vaultRouteOf(ref));
  final refresh = _Refresh();
  void update() {
    vault.value = vaultRouteOf(ref);
    refresh.notify();
  }

  ref.listen(sessionProvider, (_, next) {
    session.value = next;
    update();
  });
  ref.listen(vaultAccountProvider, (_, _) => update());
  ref.listen(currentVaultAccountProvider, (_, _) => update());
  ref.listen(vaultGateStateProvider, (_, _) => update());
  final router = GoRouter(
    refreshListenable: refresh,
    // A location no route has (an address Android hands over that is not one of the app's, such as
    // the `glance-action:/CALLBACK?...` a tap on the widget carried) is home, never "Page Not Found".
    onException: (context, state, router) => router.go('/'),
    redirect: (context, state) => sessionRedirect(session.value, state.uri, vault: vault.value),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => HomeScreen(
          // The month to open on, when a link carries one (`/?month=2026-09`).
          initialMonth: state.uri.queryParameters['month'],
          menu: (context, close) => HomeMenuLinks(close: close),
        ),
      ),
      GoRoute(
        path: '/categories/:id',
        builder: (context, state) => CategoryDetailScreen(
          // A new category replaces the screen of an earlier one.
          key: ValueKey(state.pathParameters['id']),
          categoryId: state.pathParameters['id']!,
          // The month it opens on (`?month=2026-09`), home's when it comes from a budget row.
          initialMonth: state.uri.queryParameters['month'],
          // Opened from home's Categorías tab: "back" says so.
          fromCategories: state.extra == detailFromCategories,
        ),
      ),
      // The web's pages (apps/web/app/routes.ts), under `/app` there. There is no categories page:
      // categories are managed in home's Categorías tab and in the category's detail above, so the
      // face menu's Categorías asks home for that tab (`homeViewRequestProvider`), and so does the
      // old `/categories` address: it lands on that tab, as the web's `/app/categories` does.
      GoRoute(
        path: '/categories',
        redirect: (context, state) {
          ref.read(homeViewRequestProvider.notifier).show(HomeView.budgets);
          return '/';
        },
      ),
      GoRoute(path: '/recurring', builder: (context, state) => const RecurringScreen()),
      GoRoute(path: '/import', builder: (context, state) => const ImportScreen()),
      // `/welcome/:step?`, the onboarding (the web's, outside `/app`). One screen holds all its steps,
      // so its state (what was chosen, the import, the budgets typed) lives across them: moving
      // between steps changes only the address, as the web's `shouldRevalidate` has it.
      ShellRoute(
        builder: (context, state, child) =>
            WelcomeScreen(step: state.uri.pathSegments.skip(1).firstOrNull),
        routes: [
          GoRoute(path: '/welcome', builder: (context, state) => const SizedBox.shrink()),
          GoRoute(path: '/welcome/:step', builder: (context, state) => const SizedBox.shrink()),
        ],
      ),
      GoRoute(
        path: '/insights',
        builder: (context, state) =>
            // The month the period ends at (`?month=2026-09`), home's when it comes from there.
            InsightsScreen(initialMonth: state.uri.queryParameters['month']),
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) => const ReviewScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => ReviewScreen(
              key: ValueKey(state.pathParameters['id']),
              openId: state.pathParameters['id'],
            ),
          ),
        ],
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
      GoRoute(path: '/progress', builder: (context, state) => const ProgressScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [GoRoute(path: 'about', builder: (context, state) => const AboutScreen())],
      ),
      GoRoute(path: '/loading', builder: (context, state) => const Scaffold()),
      // A `preview` account's vault: the recovery key, Unlock or Locked, until it is open.
      GoRoute(path: '/unlock', builder: (context, state) => const VaultScreen()),
      GoRoute(path: '/entry', builder: (context, state) => const EntryScreen()),
      GoRoute(
        path: '/entry/email',
        builder: (context, state) => EmailScreen(
          initialEmail: state.uri.queryParameters['email'],
          claim: state.uri.queryParameters['claim'] == '1',
        ),
      ),
      GoRoute(path: _offerPath, builder: (context, state) => const PasskeyOfferPage()),
      // The passkey PRF probe: debug builds only.
      if (kDebugMode)
        GoRoute(path: '/debug/prf', builder: (context, state) => const PrfProbeScreen()),
      GoRoute(
        path: '/auth/verify',
        builder: (context, state) => VerifyLinkScreen(
          // A new link replaces the screen of an earlier one.
          key: ValueKey(state.uri.query),
          email: state.uri.queryParameters['email'],
          code: state.uri.queryParameters['code'],
        ),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    session.dispose();
    vault.dispose();
    refresh.dispose();
  });
  return router;
});

/// Tells the router to run its redirect again.
class _Refresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
