// Cuenta y seguridad (`/settings/account`), the light version (spec 2026-11-22; twin of
// apps/web/app/features/settings/AccountScreen.tsx): the account's email, a "Entrar con tu huella"
// group, for an encrypted account a "Tus dispositivos" group and the recovery-key rows, and the
// delete row in red. A plain account has only the passkeys and the delete row. Each long
// explanation lives in the sheet or flow its row opens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import 'delete_account.dart';
import 'passkeys_section.dart';
import 'security/security_section.dart';
import 'settings_screen.dart' show settingsEmailProvider;

class AccountScreen extends ConsumerWidget {
  const AccountScreen({
    super.key,
    required this.timeZone,
    required this.passkeysGuest,
    required this.showSecurity,
  });

  /// The profile's zone: passkeys and devices are dated in it.
  final String timeZone;

  /// A guest cannot add a passkey from here (a `preview` guest can).
  final bool passkeysGuest;

  /// An encrypted account's devices and recovery key, with or without email.
  final bool showSecurity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(settingsEmailProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space4,
      children: [
        if (email != null)
          Text(
            email,
            key: const Key('settings.account.email'),
            style: LkText.bodySm.copyWith(color: context.lkColors.inkMuted),
          ),
        PasskeysSection(timeZone: timeZone, guest: passkeysGuest),
        if (showSecurity) SecuritySection(timeZone: timeZone),
        const DeleteAccountCard(),
      ],
    );
  }
}
