// Settings' "Protect your data" block (phone-first spec 5.2), at the top for a `preview` account
// without an email: the recovery key, the passkey (only where the phone reports passkey support) and
// adding an email, one settings row each (a check once done), under one short line: a list done at
// one's own pace, no count. On the iPhone the passkey is Face ID, elsewhere the fingerprint.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../settings/settings_parts.dart';
import '../theme/text_styles.dart';
import '../ui/css_text.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import 'protect_actions.dart';
import 'protect_status.dart';

class ProtectBlock extends ConsumerStatefulWidget {
  const ProtectBlock({super.key});

  @override
  ConsumerState<ProtectBlock> createState() => _ProtectBlockState();
}

class _ProtectBlockState extends ConsumerState<ProtectBlock> {
  var _busy = false;

  /// The passkey just added here gave no PRF: said under the step as text that stays.
  var _addedWithoutPrf = false;

  Future<void> _run(Future<void> Function() step) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await step();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One step as one settings row: its icon and name, then "To do" and a chevron (the row does the
  /// step) or a check once it is done. What the step is for is read, not drawn.
  Widget _step({
    required String actionKey,
    required LkIconName icon,
    required String title,
    required String lead,
    required bool done,
    required VoidCallback onPressed,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return SettingsRow(
      key: Key(done ? '$actionKey.done' : actionKey),
      icon: LkIcon(icon, size: 20, color: colors.inkMuted),
      title: title,
      semanticsHint: lead,
      trailing: done
          ? RowCustom(
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  LkIcon(LkIconName.check, size: 16, color: colors.ink),
                  Text(l10n.protectDone, style: LkText.label.copyWith(color: colors.ink)),
                ],
              ),
            )
          : RowChevron(value: l10n.protectStepTodo),
      onTap: done || _busy ? null : onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(protectStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final iphone = defaultTargetPlatform == TargetPlatform.iOS;
    final passkeyNote = _addedWithoutPrf && !status.passkey
        ? Semantics(
            liveRegion: true,
            container: true,
            child: CssParagraph(
              l10n.settingsPasskeysAddNoPrf,
              key: const Key('protect.passkeyAddNoPrf'),
              style: LkText.fieldLabel.copyWith(color: colors.ink),
            ),
          )
        : status.passkeyWithoutPrf && !status.passkey
        ? CssParagraph(
            l10n.protectPasskeyNoPrf,
            key: const Key('protect.passkeyNoPrf'),
            style: LkText.fieldLabel.copyWith(color: colors.over),
          )
        : null;
    return SettingsSection(
      key: const Key('protect.block'),
      title: l10n.protectTitle,
      lead: l10n.protectLead,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _step(
              actionKey: 'protect.recovery',
              icon: LkIconName.key,
              title: l10n.protectRecoveryTitle,
              lead: l10n.protectRecoveryLead,
              done: status.recoveryKey,
              onPressed: () => unawaited(_run(() => protectWithRecoveryKey(context, ref))),
            ),
            if (status.passkeyOffered)
              _step(
                actionKey: 'protect.passkey',
                icon: iphone ? LkIconName.shield : LkIconName.fingerprint,
                title: iphone ? l10n.protectPasskeyRowIos : l10n.protectPasskeyRow,
                lead: iphone ? l10n.protectPasskeyLeadIos : l10n.protectPasskeyLead,
                done: status.passkey,
                onPressed: () => unawaited(
                  _run(() async {
                    setState(() => _addedWithoutPrf = false);
                    await protectWithPasskey(
                      context,
                      ref,
                      onNoPrf: () {
                        if (mounted) setState(() => _addedWithoutPrf = true);
                      },
                    );
                  }),
                ),
              ),
            ?passkeyNote,
            _step(
              actionKey: 'protect.email',
              icon: LkIconName.user,
              title: l10n.protectEmailTitle,
              lead: iphone ? l10n.protectEmailLeadIos : l10n.protectEmailLead,
              done: false,
              onPressed: () => unawaited(context.push('/progress')),
            ),
          ],
        ),
      ],
    );
  }
}
