// Twin of apps/web/app/features/settings/SecuritySection.tsx: Cuenta y seguridad's encrypted part (a
// "Tus dispositivos" group and a group with the recovery key rows) for an encrypted
// (`preview`) account, with or without email (the same section for both): this phone and the other
// devices that open the data (name, added date, "Not verified" when an attestation fails), each
// other one with "Remove" (its wrap is deleted, the keys stay: `RemoveDeviceSheet`); "Connect
// another device" (`ConnectDeviceScreen`: a browser's sign-in, phone-first spec 8.1, or a new device
// to approve, by its QR or its code); "New recovery key"; "Change keys" (a rotation that removes no device, `ChangeKeysSheet`);
// and how many records could not be read, when any. The sensitive steps (removing a device, making
// a new key, showing it, changing the keys) ask the phone's screen lock first (spec 7.7, D17), which
// replaces the web's passkey touch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../local/rotate.dart' show NewRecoveryKey;
import '../../protect/protect_actions.dart' show markRecoveryKeySaved;
import '../../protect/protect_status.dart' show protectStatusProvider, recoveryKeySavedAt;
import '../../vault/encryption_mode.dart' show currentVaultAccountProvider;
import '../../security/screen_lock.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.g.dart';
import '../../ui/confirm_sheet.dart';
import '../../ui/css_text.dart';
import '../../ui/lk_icons.dart';
import '../../ui/lk_theme.dart';
import '../../ui/toast.dart';
import '../../vault/vault_providers.dart' show vaultSessionProvider;
import '../passkeys_section.dart' show passkeyDay;
import '../settings_parts.dart';
import 'change_keys_sheet.dart';
import 'connect_device_screen.dart';
import 'recovery_setup_page.dart';
import 'remove_device_sheet.dart';
import 'security_api.dart';
import 'security_model.dart';

/// Whether this account has no recovery key to type for the screen lock's fallback: a guest who
/// never saved a shown key (ruling 3). An email account whose settings predate
/// `recoveryKeySavedAt` still is asked for it (D17). Shared by Remove, Change keys and New
/// recovery key here, and by the sign-in notice's "That wasn't me".
Future<bool> noKeyToTypeYet(WidgetRef ref) async {
  final anonymous = ref.read(currentVaultAccountProvider)?.profile.isAnonymous ?? false;
  final session = ref.read(vaultSessionProvider);
  if (!anonymous || session == null) return false;
  try {
    return await recoveryKeySavedAt(session.store) == null;
  } on Object {
    // Unreadable: the key is asked, as for any account.
    return false;
  }
}

class SecuritySection extends ConsumerStatefulWidget {
  const SecuritySection({super.key, required this.timeZone});

  /// The profile's zone: a device is dated in it.
  final String timeZone;

  @override
  ConsumerState<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<SecuritySection> {
  var _busy = false;

  void _changed() => ref.invalidate(securitySnapshotProvider);

  /// "Connect another device": a browser or a phone joins as a device, so the list is read again
  /// after.
  Future<void> _connect() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (route) => ConnectDeviceScreen(onDone: () => Navigator.of(route).pop()),
      ),
    );
    _changed();
  }

  Future<void> _remove(SecurityApi security, DeviceRow row, bool hasPasskeys) async {
    // Set before the lock is asked: a double tap opens neither two prompts nor two sheets.
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final noKeyYet = await _noKeyYet();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final ok = await confirmSensitive(
        context,
        ref,
        reason: l10n.settingsSecurityLockRemove,
        checkRecoveryKey: security.checkRecoveryKey,
        noKeyYet: noKeyYet,
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

  /// "Change keys" (the web's twin): the screen lock confirms, then the sheet rotates with nothing
  /// removed (the typed recovery key, or a new one shown first). The keys are read again after,
  /// whatever happened (a refusal may mean another device changed them).
  Future<void> _changeKeys(SecurityApi security, bool hasPasskeys) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final noKeyYet = await _noKeyYet();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final ok = await confirmSensitive(
        context,
        ref,
        reason: l10n.settingsSecurityLockChangeKeys,
        checkRecoveryKey: security.checkRecoveryKey,
        noKeyYet: noKeyYet,
      );
      if (!ok || !mounted) return;
      await ChangeKeysSheet.open(context, security: security, hasPasskeys: hasPasskeys);
      _changed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _noKeyYet() => noKeyToTypeYet(ref);

  /// "New recovery key" (spec 7.4's "ask again"): the screen lock confirms, then the new key is
  /// shown with its four-character check and committed only after the check (D17).
  Future<void> _newKey(SecurityApi security) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    setState(() => _busy = true);
    try {
      // What a new key does comes first (the row has only one line); then the screen lock.
      final go = await ConfirmSheet.show(
        context,
        title: l10n.settingsSecurityNewKeyTitle,
        body: l10n.settingsSecurityRecoveryLead,
        confirmLabel: l10n.settingsSecurityNewKeyContinue,
        confirmKey: const Key('security.newKey.continue'),
        onConfirm: () async {},
      );
      if (!go || !mounted) return;
      final session = ref.read(vaultSessionProvider);
      final noKeyYet = await _noKeyYet();
      if (!mounted) return;
      final ok = await confirmSensitive(
        context,
        ref,
        reason: l10n.settingsSecurityLockNewKey,
        checkRecoveryKey: security.checkRecoveryKey,
        noKeyYet: noKeyYet,
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
        refused: () => prepared.refused,
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
      // A key the person saw is saved: "Protect your data" counts it, on every phone of the account.
      if (session != null) {
        unawaited(
          markRecoveryKeySaved(
            session,
            DateTime.now(),
          ).then((_) => ref.invalidate(protectStatusProvider)).catchError((Object _) {}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _deviceItem(AppLocalizations l10n, DeviceRow row, SecurityApi security, bool hasPasskeys) {
    final colors = context.lkColors;
    final name = row.label ?? l10n.settingsSecurityUnnamed;
    final created = DateTime.tryParse(row.createdAt ?? '');
    final line = [
      if (created != null)
        l10n.settingsSecurityAdded(passkeyDay(created, l10n.localeName, widget.timeZone)),
      if (!row.verified) l10n.settingsSecurityNotVerified,
    ].join(' · ');
    return SettingsRow(
      key: Key('security.device.${row.id}'),
      icon: LkIcon(deviceIconFor(row.label), size: 20, color: colors.inkMuted),
      title: name,
      line: line.isEmpty ? null : line,
      trailing: row.thisPhone
          ? RowChip(l10n.settingsSecurityThisPhone)
          : row.removable
          ? RowTrash(
              buttonKey: Key('security.remove.${row.id}'),
              label: l10n.settingsSecurityRemoveLabel(name),
              onTap: () => unawaited(_remove(security, row, hasPasskeys)),
            )
          : const RowNone(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securityApiProvider);
    // No open vault (locked, or not an encrypted account): nothing to show.
    if (security == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
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
    Widget note(Widget child) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), child: child);
    return Column(
      key: const Key('settings.card.security'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        SettingsGroup(
          head: SettingsGroupHead(
            icon: LkIcon(LkIconName.phone, size: 22, color: colors.brand),
            title: l10n.settingsSecurityTitle,
            line: l10n.settingsSecurityLead,
          ),
          rows: [
            if (snapshot.hasError && data == null)
              note(
                CssParagraph(
                  l10n.settingsSecurityLoadFailed,
                  style: LkText.bodySm.copyWith(color: colors.inkMuted),
                ),
              ),
            if (rows != null) ...[
              if (rows.thisPhone != null) _deviceItem(l10n, rows.thisPhone!, security, hasPasskeys),
              for (final row in rows.others) _deviceItem(l10n, row, security, hasPasskeys),
            ],
            SettingsRow(
              key: const Key('security.connect'),
              icon: LkIcon(LkIconName.plus, size: 20, color: colors.inkMuted),
              title: l10n.settingsSecurityConnect,
              trailing: const RowNone(),
              onTap: () => unawaited(_connect()),
            ),
            if (unreadable > 0)
              note(
                CssParagraph(
                  '${l10n.settingsSecurityUnreadable(unreadable)}. ${l10n.settingsSecurityUnreadableLead}',
                  style: LkText.fieldLabel.copyWith(color: colors.inkMuted),
                ),
              ),
          ],
        ),
        SettingsGroup(
          rows: [
            SettingsRow(
              key: const Key('security.newKey'),
              icon: LkIcon(LkIconName.key, size: 20, color: colors.inkMuted),
              title: l10n.settingsSecurityRecoveryTitle,
              line: l10n.settingsSecurityRecoveryLine,
              trailing: const RowChevron(),
              onTap: _busy ? null : () => unawaited(_newKey(security)),
            ),
            SettingsRow(
              key: const Key('security.changeKeys'),
              icon: LkIcon(LkIconName.key, size: 20, color: colors.inkMuted),
              title: l10n.settingsSecurityChangeKeys,
              line: l10n.settingsSecurityChangeKeysLine,
              trailing: const RowChevron(),
              onTap: _busy ? null : () => unawaited(_changeKeys(security, hasPasskeys)),
            ),
          ],
        ),
      ],
    );
  }
}
