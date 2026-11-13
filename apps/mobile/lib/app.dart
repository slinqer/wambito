import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feedback/celebration.dart';
import 'feedback/feedback.dart';
import 'home/widget_sync.dart';
import 'capture/prewarm.dart';
import 'launch/launch_links.dart';
import 'l10n/app_localizations.dart';
import 'notices/notice_sync.dart';
import 'router.dart';
import 'settings/locale_resolution.dart';
import 'settings/preferences.dart';
import 'theme/theme.dart';
import 'ui/toast.dart';
import 'vault/preview_sync.dart';

/// What goes above every screen and sheet: the celebration (the web's `Celebration`) over the toasts
/// (`ToastProvider`), so that it keeps clear of them. Tests that build their own `MaterialApp` put
/// it in its `builder`.
Widget withAppHosts(Widget child, {bool animateToastBar = true, bool celebrate = true}) {
  final toasts = ToastHost(animateBar: animateToastBar, child: child);
  return celebrate ? CelebrationHost(child: toasts) : toasts;
}

/// Whether a toast's time bar runs: always, except in tests that settle the frames.
final toastBarAnimatesProvider = Provider<bool>((ref) => true);

/// The app shell: theme (night by default), es and en copy, and routes.
class WambitoApp extends ConsumerWidget {
  const WambitoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loads the sounds and reads the sound setting at the start, so the first save is not late.
    ref.watch(feedbackProvider);
    // Copies the hide-amount and theme choices into the home-screen widget's snapshot as they change.
    ref.watch(widgetSyncProvider);
    // Opens the add sheet or quick capture for the widget's ＋ and 🎤 and the Quick Settings tile.
    ref.watch(launchLinksProvider);
    // Loads the speech model in the background (after a first capture), so 🎤 listens at once.
    ref.watch(voicePrewarmProvider);
    // Schedules the two local notices ("Hoy vence…" at 9:00, the guest warning) and asks the
    // notification permission, once, when one first becomes relevant.
    ref.watch(noticeSyncProvider);
    // Tells the phone's background jobs and the widget whether the account is encrypted (`preview`):
    // none of them may send or fetch finance data for it.
    ref.watch(previewSyncProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: dayTheme,
      darkTheme: nightTheme,
      // Night unless the person picked day, or the phone's own mode, in Settings.
      themeMode: ref.watch(themeModeProvider),
      // The phone's language unless the person picked Spanish or English in Settings.
      locale: ref.watch(localeOverrideProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Spanish unless the phone asks for a language the app has.
      localeResolutionCallback: resolveAppLocale,
      // The web's `Celebration` and `ToastProvider`, above every screen and sheet: the toasts under
      // the party (it keeps clear of them).
      builder: (context, child) =>
          withAppHosts(child!, animateToastBar: ref.watch(toastBarAnimatesProvider)),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
