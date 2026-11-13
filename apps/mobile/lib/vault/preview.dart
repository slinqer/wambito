import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import 'encryption_mode.dart';

/// Whether the signed-in session's account is `preview`: its finances live only in the vault on this
/// phone. False when signed out, for `plain`, and while the mode is loading or failed (read from
/// [currentVaultAccountProvider], never the previous session's value).
///
/// What stage 3a leaves out (automatic capture, the home widget, due notices, export, import and
/// the assistants) is not offered to such an account: each shows [ComingSoonNotice], and nothing of
/// it sends or fetches finance data.
final isPreviewProvider = Provider<bool>(
  (ref) => ref.watch(currentVaultAccountProvider)?.mode == EncryptionMode.preview,
);

/// "Coming soon with encryption": what stands where a feature of the phone is not ported to an
/// encrypted account yet.
class ComingSoonNotice extends StatelessWidget {
  const ComingSoonNotice({super.key});

  @override
  Widget build(BuildContext context) => CssParagraph(
    AppLocalizations.of(context).comingSoonWithEncryption,
    style: LkText.bodySm.copyWith(color: context.lkColors.inkMuted),
  );
}
