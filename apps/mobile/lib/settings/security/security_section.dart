// Twin of apps/web/app/features/settings/SecuritySection.tsx: Settings → Security for an encrypted
// (`preview`) account. A guest (no recovery key) gets only "Approve a new device": nothing is loaded
// for it. Otherwise: this phone and the other devices that open the data (name, added date, "Not
// verified" when an attestation fails), each other one with "Remove" (a key rotation,
// `RemoveDeviceSheet`); "Approve a new device"; "New recovery key"; and how many records could not be
// read, when any. The sensitive steps (removing a device, making a new key, showing it) ask the
// phone's screen lock first (spec 7.7, D17), which replaces the web's passkey touch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../local/rotate.dart' show NewRecoveryKey;
import '../../security/screen_lock.dart';
import '../../theme/surfaces.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.g.dart';
import '../../ui/css_text.dart';
import '../../ui/lk_theme.dart';
import '../../ui/press_button.dart';
import '../../ui/toast.dart';
import '../passkeys_section.dart' show passkeyDay;
import '../settings_parts.dart';
import 'approve_device_screen.dart';
import 'recovery_setup_page.dart';
import 'remove_device_sheet.dart';
import 'security_api.dart';
import 'security_model.dart';

class SecuritySection extends ConsumerStatefulWidget {
  const SecuritySection({super.key, required this.timeZone, required this.guest});

  /// The profile's zone: a device is dated in it.
  final String timeZone;

  /// A guest's reduced section: only approving a new device.
  final bool guest;

  @override
  ConsumerState<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<SecuritySection> {
  var _busy = false;

  void _changed() => ref.invalidate(securitySnapshotProvider);

  Future<void> _approve(SecurityApi security) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (route) => ApproveDeviceScreen(
          options: security.pairing,
          findPairing: (options, {code, qr}) => security.findPairing(code: code, qr: qr),
          onDone: () => Navigator.of(route).pop(),
        ),
      ),
    );
    if (!widget.guest) _changed();
  }

  Future<void> _remove(SecurityApi security, DeviceRow row, bool hasPasskeys) async {
    // Set before the lock is asked: a double tap opens neither two prompts nor two sheets.
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final l10n = AppLocalizations.of(context);
      final ok = await confirmSensitive(
        context,
        ref,
        reason: l10n.settingsSecurityLockRemove,
        checkRecoveryKey: security.checkRecoveryKey,
      );
      if (!ok || !mounted) return;
      await RemoveDeviceSheet.show(
        context,
        device: row,
        security: security,
        hasPasskeys: hasPasskeys,
        onChanged: _changed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "New recovery key" (spec 7.4's "ask again"): the screen lock confirms, then the new key is
  /// shown with its four-character check and committed only after the check (D17).
  Future<void> _newKey(SecurityApi security) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    setState(() => _busy = true);
    try {
      final ok = await confirmSensitive(
        context,
        ref,
        reason: l10n.settingsSecurityLockNewKey,
        checkRecoveryKey: security.checkRecoveryKey,
      );
      if (!ok || !mounted) return;
      final NewRecoveryKey prepared;
      try {
        prepared = await security.newRecoveryKey();
      } on Object catch (error) {
        toasts.say(
          codeOf(error) == 'offline'
              ? l10n.vaultUnlockErrorOffline
              : l10n.settingsSecurityNewKeyFailed,
          error: true,
        );
        return;
      }
      if (!mounted) {
        prepared.forget();
        return;
      }
      final outcome = await RecoverySetupPage.open<void>(
        context,
        recoveryKey: prepared.recoveryKey,
        commit: prepared.commit,
      );
      // Saved, gave up or refused for sure: whatever it held is let go.
      prepared.forget();
      if (outcome == null) return;
      if (outcome.refused != null) {
        // Refused for sure: the sync picks up the other device's keys, the list follows.
        unawaited(security.reloadKeys().catchError((Object _) {}));
        _changed();
        toasts.say(l10n.settingsSecurityNewKeyRotatedElsewhere, error: true);
        return;
      }
      toasts.say(l10n.settingsSecurityNewKeySaved);
      _changed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _deviceItem(AppLocalizations l10n, DeviceRow row, SecurityApi security, bool hasPasskeys) {
    final colors = context.lkColors;
    final lk = context.lk;
    final name = row.label ?? l10n.settingsSecurityUnnamed;
    final created = DateTime.tryParse(row.createdAt ?? '');
    final muted = LkText.fieldLabel.copyWith(color: colors.inkMuted);
    final strong = LkText.fieldLabel.copyWith(color: colors.ink, fontWeight: FontWeight.w700);
    return Container(
      key: Key('security.device.${row.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: LkSurface.rowCard(lk),
      child: Row(
        spacing: 10,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LkText.body.copyWith(color: colors.ink),
                ),
                Wrap(
                  spacing: WambitoTokens.space2,
                  children: [
                    if (row.thisPhone) Text(l10n.settingsSecurityThisPhone, style: strong),
                    if (created != null)
                      Text(
                        l10n.settingsSecurityAdded(
                          passkeyDay(created, l10n.localeName, widget.timeZone),
                        ),
                        style: muted,
                      ),
                    if (!row.verified)
                      Text(
                        l10n.settingsSecurityNotVerified,
                        style: muted.copyWith(color: colors.over, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (row.removable)
            PressButton.text(
              l10n.settingsSecurityRemove,
              key: Key('security.remove.${row.id}'),
              tone: PressTone.ghost,
              size: PressSize.sm,
              semanticLabel: l10n.settingsSecurityRemoveLabel(name),
              onPressed: () => unawaited(_remove(security, row, hasPasskeys)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securityApiProvider);
    // No open vault (locked, or not an encrypted account): nothing to show.
    if (security == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final approve = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WambitoTokens.space2,
      children: [
        SettingLabel(label: l10n.settingsSecurityApprove, hint: l10n.settingsSecurityApproveLead),
        PressButton.text(
          l10n.settingsSecurityApprove,
          key: const Key('security.approve'),
          tone: PressTone.secondary,
          onPressed: () => unawaited(_approve(security)),
        ),
      ],
    );
    if (widget.guest) {
      return SettingsSection(
        key: const Key('settings.card.security'),
        title: l10n.settingsSecurityTitle,
        lead: l10n.settingsSecurityGuestLead,
        children: [approve],
      );
    }
    final snapshot = ref.watch(securitySnapshotProvider);
    final data = snapshot.value;
    final rows = data == null
        ? null
        : deviceRows(
            wraps: data.wraps,
            ownId: data.ownId,
            revoked: data.revoked,
            verified: data.verified,
          );
    final hasPasskeys = data != null && anyPasskeyWrap(data.wraps);
    final unreadable = data?.unreadable ?? 0;
    return SettingsSection(
      key: const Key('settings.card.security'),
      title: l10n.settingsSecurityTitle,
      lead: l10n.settingsSecurityLead,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            if (snapshot.hasError && data == null)
              CssParagraph(
                l10n.settingsSecurityLoadFailed,
                style: LkText.bodySm.copyWith(color: colors.inkMuted),
              ),
            if (rows != null) ...[
              if (rows.thisPhone != null) _deviceItem(l10n, rows.thisPhone!, security, hasPasskeys),
              for (final row in rows.others) _deviceItem(l10n, row, security, hasPasskeys),
            ],
          ],
        ),
        approve,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space2,
          children: [
            SettingLabel(
              label: l10n.settingsSecurityRecoveryTitle,
              hint: l10n.settingsSecurityRecoveryLead,
            ),
            PressButton.text(
              l10n.settingsSecurityNewRecovery,
              key: const Key('security.newKey'),
              tone: PressTone.secondary,
              onPressed: _busy ? null : () => unawaited(_newKey(security)),
            ),
          ],
        ),
        if (unreadable > 0)
          SettingLabel(
            label: l10n.settingsSecurityUnreadable(unreadable),
            hint: l10n.settingsSecurityUnreadableLead,
          ),
      ],
    );
  }
}
