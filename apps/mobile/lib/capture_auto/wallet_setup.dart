// "Configurar en Atajos" on the iPhone (spec 2026-11-22-ios-wallet-capture-design.md, section 3.4):
// on iOS 27, once the ready-made shortcut has an iCloud link, four steps and "Instalar el atajo";
// before iOS 27 (or without the link) the guide to build the Transaction automation by hand, and
// "Abrir Atajos".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../settings/url_opener.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import 'capture_platform.dart';

/// The iCloud link of the ready-made shortcut (a Transaction automation, all cards, no confirmation,
/// whose one action is "Anotar pago de Wallet" with the trigger's Amount, Merchant and Card). Empty
/// until the founder shares it from an iPhone (docs/mobile/ios.md); while empty the guide shows.
const walletShortcutUrl = '';

/// The first iOS whose shared shortcuts keep their automation.
const _installableFrom = 27;

/// Opens the setup sheet for an iPhone on [iosMajor]. [shortcutUrl] is [walletShortcutUrl] (tests
/// pass another).
Future<void> showWalletSetup(
  BuildContext context, {
  required int iosMajor,
  String shortcutUrl = walletShortcutUrl,
}) async {
  final l10n = AppLocalizations.of(context);
  final install = iosMajor >= _installableFrom && shortcutUrl.isNotEmpty;
  await LkSheet.show<void>(
    context,
    title: l10n.walletSetupTitle,
    children: [
      KeyedSubtree(
        key: const Key('walletSetup.sheet'),
        child: install ? _InstallSteps(url: shortcutUrl) : const _Guide(),
      ),
    ],
  );
}

class _InstallSteps extends ConsumerWidget {
  const _InstallSteps({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final steps = [
      l10n.walletSetupStep1,
      l10n.walletSetupStep2,
      l10n.walletSetupStep3,
      l10n.walletSetupStep4,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space3,
        children: [
          for (final (i, step) in steps.indexed)
            Row(
              key: Key('walletSetup.step${i + 1}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WambitoTokens.space3,
              children: [
                Text('${i + 1}.', style: LkText.step.copyWith(color: colors.brand)),
                Expanded(
                  child: CssParagraph(step, style: LkText.body.copyWith(color: colors.ink)),
                ),
              ],
            ),
          const SizedBox(height: WambitoTokens.space2),
          PressButton.text(
            l10n.walletSetupInstall,
            key: const Key('walletSetup.install'),
            onPressed: () => unawaited(ref.read(urlOpenerProvider).open(Uri.parse(url))),
          ),
        ],
      ),
    );
  }
}

class _Guide extends ConsumerWidget {
  const _Guide();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space4,
        children: [
          // One paragraph per step: a paragraph collapses line breaks.
          Column(
            key: const Key('walletSetup.guide'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space2,
            children: [
              for (final line in l10n.walletSetupGuide.split('\n'))
                CssParagraph(line, style: LkText.body.copyWith(color: colors.ink)),
            ],
          ),
          PressButton.text(
            l10n.walletSetupOpenShortcuts,
            key: const Key('walletSetup.openShortcuts'),
            onPressed: () => unawaited(ref.read(autoCapturePlatformProvider).openShortcuts()),
          ),
        ],
      ),
    );
  }
}
