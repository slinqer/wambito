// Twin of apps/web/app/features/settings/RemoveDeviceSheet.tsx. Removing a device is one tap: its
// wrap is deleted and its session ends (`SecurityApi.removeDevice`, `DELETE /v2/keys/{id}`). The data
// key does not change and no recovery key is asked; changing the keys is its own action
// (`ChangeKeysSheet`). The caller asked the screen lock first (confirmSensitive). A wrap already gone
// (removed meanwhile from another device) counts as removed. Offline or any other failure keeps the
// sheet and says so; nothing is half-done.
//
// From the sign-in notice's "That wasn't me" (`suggestChangeKeys`), the sheet stays on a done step
// that suggests changing the keys (someone else may have copied the data key) and opens
// `ChangeKeysSheet` from there. Any other removal closes the sheet and says it with a toast.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../entry/sign_in_frame.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.g.dart';
import '../../ui/css_text.dart';
import '../../ui/lk_theme.dart';
import '../../ui/press_button.dart';
import '../../ui/sheet.dart';
import '../../ui/toast.dart';
import 'change_keys_sheet.dart';
import 'security_api.dart';
import 'security_model.dart';

/// What stopped a removal, shown under the button.
enum _Problem { offline, failed }

/// How the sheet ended.
enum _Outcome { removed, changeKeys }

abstract final class RemoveDeviceSheet {
  /// Opens the sheet for [device] (never this phone's own: the list does not offer it).
  /// [onChanged]: the account's keys changed: read them again. [hasPasskeys] goes to
  /// `ChangeKeysSheet` when the done step opens it.
  static Future<void> show(
    BuildContext context, {
    required DeviceRow device,
    required SecurityApi security,
    required VoidCallback onChanged,
    bool suggestChangeKeys = false,
    bool hasPasskeys = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    final name = device.label ?? l10n.settingsSecurityUnnamed;
    final locked = ValueNotifier(false);
    final _Outcome? outcome;
    try {
      outcome = await LkSheet.show<_Outcome>(
        context,
        title: l10n.settingsSecurityRemoveTitle(name),
        locked: locked,
        children: [
          _RemoveBody(
            device: device,
            security: security,
            suggestChangeKeys: suggestChangeKeys,
            onChanged: onChanged,
            locked: locked,
          ),
        ],
      );
    } finally {
      locked.dispose();
    }
    if (outcome == _Outcome.removed) toasts.say(l10n.settingsSecurityRemovedDone(name));
    if (outcome == _Outcome.changeKeys && context.mounted) {
      await ChangeKeysSheet.open(context, security: security, hasPasskeys: hasPasskeys);
      onChanged();
    }
  }
}

class _RemoveBody extends StatefulWidget {
  const _RemoveBody({
    required this.device,
    required this.security,
    required this.suggestChangeKeys,
    required this.onChanged,
    required this.locked,
  });

  final DeviceRow device;
  final SecurityApi security;
  final bool suggestChangeKeys;
  final VoidCallback onChanged;
  final ValueNotifier<bool> locked;

  @override
  State<_RemoveBody> createState() => _RemoveBodyState();
}

class _RemoveBodyState extends State<_RemoveBody> {
  var _busy = false;
  var _done = false;
  _Problem? _problem;

  Future<void> _remove() async {
    if (_busy) return;
    widget.locked.value = true;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.security.removeDevice(widget.device.id);
    } on Object catch (error) {
      widget.locked.value = false;
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = codeOf(error) == 'offline' ? _Problem.offline : _Problem.failed;
        });
      }
      return;
    }
    widget.locked.value = false;
    widget.onChanged();
    if (!mounted) return;
    if (!widget.suggestChangeKeys) {
      Navigator.of(context).pop(_Outcome.removed);
      return;
    }
    setState(() {
      _busy = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: _done ? _doneView(l10n) : _askView(l10n),
    );
  }

  Widget _doneView(AppLocalizations l10n) {
    final colors = context.lkColors;
    final name = widget.device.label ?? l10n.settingsSecurityUnnamed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        Semantics(
          header: true,
          child: CssParagraph(
            l10n.settingsSecurityRemovedDone(name),
            style: LkText.body.copyWith(color: colors.ink, fontWeight: FontWeight.w700),
          ),
        ),
        CssParagraph(
          l10n.settingsSecurityChangeKeysSuggest,
          style: LkText.body.copyWith(color: colors.ink),
        ),
        PressButton.text(
          l10n.settingsSecurityChangeKeys,
          key: const Key('security.remove.changeKeys'),
          tone: PressTone.secondary,
          onPressed: () => Navigator.of(context).pop(_Outcome.changeKeys),
        ),
      ],
    );
  }

  Widget _askView(AppLocalizations l10n) {
    final colors = context.lkColors;
    final problem = _problem;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        CssParagraph(
          l10n.settingsSecurityRemoveBody,
          style: LkText.body.copyWith(color: colors.ink),
        ),
        PressButton.text(
          _busy ? l10n.settingsSecurityRemoving : l10n.settingsSecurityRemove,
          key: const Key('security.remove.confirm'),
          tone: PressTone.secondary,
          onPressed: _busy ? null : () => unawaited(_remove()),
        ),
        if (problem != null)
          FieldError(switch (problem) {
            _Problem.offline => l10n.vaultUnlockErrorOffline,
            _Problem.failed => l10n.settingsSecurityRemoveFailed,
          }),
      ],
    );
  }
}
