import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/session.dart';
import '../home/home_header.dart';
import '../home/home_screen.dart' show HomeView, homeViewRequestProvider;
import '../l10n/app_localizations.dart';
import '../theme/tokens.g.dart';
import '../vault/preview.dart' show isPreviewProvider;

/// What the face button's menu on home holds, as the web's does (`HomeHeader`'s sections):
/// Recurrentes, Categorías and Ajustes, and, for a guest, "Guarda tu progreso" first ("Crear tu
/// cuenta" for a `preview` guest). Each closes
/// the menu and goes there. The web's Categorías is its categories page; the app has none, its
/// categories are home's Categorías tab, so that is shown.
class HomeMenuLinks extends ConsumerWidget {
  const HomeMenuLinks({super.key, required this.close});

  /// Closes the menu.
  final VoidCallback close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final anyGuest = ref.watch(sessionProvider.select((s) => s.isGuest));
    final preview = ref.watch(isPreviewProvider);
    // A `plain` guest saves their progress; a `preview` guest creates their account (adding an
    // email, the last step of "Protect your data"). Both lead to /progress.
    final guest = anyGuest && !preview;
    final createAccount = anyGuest && preview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space1,
      children: [
        if (guest)
          HomeMenuLink(
            key: const Key('home.saveProgress'),
            label: l10n.progressTitle,
            onPressed: () {
              close();
              context.push('/progress');
            },
          ),
        if (createAccount)
          HomeMenuLink(
            key: const Key('home.createAccount'),
            label: l10n.protectEmailTitle,
            onPressed: () {
              close();
              context.push('/progress');
            },
          ),
        HomeMenuLink(
          key: const Key('home.recurring'),
          label: l10n.homeMenuRecurring,
          onPressed: () {
            close();
            context.push('/recurring');
          },
        ),
        HomeMenuLink(
          key: const Key('home.categories'),
          label: l10n.homeMenuCategories,
          onPressed: () {
            close();
            ref.read(homeViewRequestProvider.notifier).show(HomeView.budgets);
          },
        ),
        HomeMenuLink(
          key: const Key('home.settings'),
          label: l10n.settingsOpenLabel,
          onPressed: () {
            close();
            context.push('/settings');
          },
        ),
      ],
    );
  }
}
