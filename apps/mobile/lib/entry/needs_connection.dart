import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/tokens.g.dart';
import '../ui/press_button.dart';
import 'sign_in_frame.dart';

/// The welcome's answer to a "Start" without network on a server not known to make encrypted users
/// (ruling 8): Wambi says it needs a connection this once, and "Try again" starts again. Nothing
/// was made.
class NeedsConnection extends StatelessWidget {
  const NeedsConnection({super.key, required this.onTryAgain});

  /// "Try again"; null while a try runs.
  final VoidCallback? onTryAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('entry.needsConnection'),
      mainAxisSize: MainAxisSize.min,
      spacing: WambitoTokens.space3,
      children: [
        Semantics(liveRegion: true, child: EntryLead(l10n.entryNeedsConnection, ink: true)),
        SizedBox(
          width: double.infinity,
          child: PressButton.text(
            l10n.entryTryAgain,
            key: const Key('entry.tryAgain'),
            tone: PressTone.secondary,
            onPressed: onTryAgain,
          ),
        ),
      ],
    );
  }
}
