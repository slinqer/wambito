// Settings' "Protect your data" block (phone-first spec 5.2), at the top for a `preview` account
// without an email: the recovery key, the passkey (only where the phone reports passkey support) and
// adding an email. It says "N of 2" until one of the first two is done, then stays as a quiet list.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../settings/settings_parts.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import 'protect_actions.dart';
import 'protect_status.dart';

class ProtectBlock extends ConsumerStatefulWidget {
  const ProtectBlock({super.key});

  @override
  ConsumerState<ProtectBlock> createState() => _ProtectBlockState();
}

class _ProtectBlockState extends ConsumerState<ProtectBlock> {
  var _busy = false;

  Future<void> _run(Future<void> Function() step) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await step();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _step({
    required String title,
    required String lead,
    required bool done,
    required String actionKey,
    required String actionLabel,
    required VoidCallback onPressed,
    Widget? note,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WambitoTokens.space2,
      children: [
        SettingLabel(label: title, hint: lead),
        ?note,
        if (done)
          Text(
            l10n.protectDone,
            key: Key('$actionKey.done'),
            style: LkText.fieldLabel.copyWith(color: colors.ink, fontWeight: FontWeight.w700),
          )
        else
          PressButton.text(
            actionLabel,
            key: Key(actionKey),
            tone: PressTone.secondary,
            onPressed: _busy ? null : onPressed,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(protectStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return SettingsSection(
      key: const Key('protect.block'),
      title: l10n.protectTitle,
      lead: l10n.protectLead,
      children: [
        if (!status.protected)
          Text(
            l10n.protectCount(status.done),
            key: const Key('protect.count'),
            style: LkText.fieldLabel.copyWith(color: colors.inkMuted, fontWeight: FontWeight.w700),
          ),
        _step(
          title: l10n.protectRecoveryTitle,
          lead: l10n.protectRecoveryLead,
          done: status.recoveryKey,
          actionKey: 'protect.recovery',
          actionLabel: l10n.protectRecoveryGo,
          onPressed: () => unawaited(_run(() => protectWithRecoveryKey(context, ref))),
        ),
        if (status.passkeyOffered)
          _step(
            title: l10n.protectPasskeyTitle,
            lead: l10n.protectPasskeyLead,
            done: status.passkey,
            actionKey: 'protect.passkey',
            actionLabel: l10n.protectPasskeyGo,
            onPressed: () => unawaited(_run(() => protectWithPasskey(context, ref))),
            note: status.passkeyWithoutPrf && !status.passkey
                ? CssParagraph(
                    l10n.protectPasskeyNoPrf,
                    key: const Key('protect.passkeyNoPrf'),
                    style: LkText.fieldLabel.copyWith(color: colors.over),
                  )
                : null,
          ),
        _step(
          title: l10n.protectEmailTitle,
          lead: l10n.protectEmailLead,
          done: false,
          actionKey: 'protect.email',
          actionLabel: l10n.protectEmailGo,
          onPressed: () => unawaited(context.push('/progress')),
        ),
      ],
    );
  }
}
