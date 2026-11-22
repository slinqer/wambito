// "Entrar con tu huella" of the web's Settings (apps/web/app/features/settings/PasskeysSection.tsx):
// the person's passkeys, each with its name and when it was made, and its own "Eliminar" after
// asking; "Agregar una huella" where the phone can make one. Closing the phone's prompt is silent,
// as on sign-in. An encrypted account's new passkey that gives no PRF is kept, and the section says
// so at once in text that stays (`settingsPasskeysAddNoPrf`), not a toast.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/parser/dates.dart';
import '../l10n/app_localizations.dart';
import '../local/keys_error.dart';
import '../local/prf.dart' show PasskeyPrf;
import '../recurring/recurring_row.dart' show formatRecurringDate;
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/css_text.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/toast.dart';
import 'passkeys_settings.dart';
import 'security/security_api.dart';
import 'security/security_model.dart';
import 'settings_parts.dart';

/// The account's passkeys, read when Settings opens and again after an add or a delete.
final settingsPasskeyListProvider = FutureProvider.autoDispose<List<PasskeyItem>>(
  (ref) => ref.watch(settingsPasskeysProvider).list(),
  // The web's card says it could not load them; opening Settings again asks again.
  retry: (_, _) => null,
);

/// Whether this phone can make a passkey, asked once.
final _passkeysCanBeMadeProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(settingsPasskeysProvider).supported(),
);

/// A day as `2 oct 2026` (es) or `Oct 2, 2026` (en), in the person's time zone.
String passkeyDay(DateTime at, String locale, String timeZone) =>
    formatRecurringDate(todayIn(timeZone, at.toUtc()), locale);

class PasskeysSection extends ConsumerStatefulWidget {
  const PasskeysSection({super.key, required this.timeZone, required this.guest});

  /// The profile's zone: a passkey is dated in it.
  final String timeZone;

  /// A guest cannot add a passkey from here: they save their progress with an email first.
  final bool guest;

  @override
  ConsumerState<PasskeysSection> createState() => _PasskeysSectionState();
}

class _PasskeysSectionState extends ConsumerState<PasskeysSection> {
  var _adding = false;

  /// The passkey being turned on for the data, and one whose provider gives no PRF (said under it).
  String? _turningOn;
  String? _noPrf;

  /// The passkey just added gave no PRF: it signs in only. Said as text that stays, until the next
  /// add or leaving Settings.
  var _addedWithoutPrf = false;

  /// The open vault's keys: which passkeys open the data, "Turn on" for the others. Null for an
  /// account with no vault on the phone.
  SecurityApi? get _security => ref.read(securityApiProvider);

  Future<void> _turnOn(PasskeyItem item) async {
    final security = _security;
    final credentialId = item.credentialId;
    if (security == null || credentialId == null || _turningOn != null) return;
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    setState(() {
      _turningOn = item.id;
      _noPrf = null;
    });
    try {
      final PasskeyPrf? touched;
      try {
        touched = await security.evaluatePrf([credentialId]);
      } on Object catch (problem) {
        if (problem is KeysError && problem.code == 'no_prf') {
          if (mounted) setState(() => _noPrf = item.id);
        } else {
          toasts.say(l10n.settingsPasskeysTurnOnFailed, error: true);
        }
        return;
      }
      if (touched == null) return;
      try {
        await security.addPasskeyWrap(touched);
      } on Object {
        toasts.say(l10n.settingsPasskeysTurnOnFailed, error: true);
        return;
      } finally {
        touched.prf.fillRange(0, touched.prf.length, 0);
      }
      toasts.say(l10n.settingsPasskeysTurnedOn);
      ref.invalidate(securitySnapshotProvider);
    } finally {
      if (mounted) setState(() => _turningOn = null);
    }
  }

  Future<void> _add() async {
    if (_adding) return;
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    setState(() {
      _adding = true;
      _addedWithoutPrf = false;
    });
    // The new passkey itself gave no PRF (not a PRF whose wrap could not be saved).
    var withoutPrf = false;
    try {
      final security = widget.guest ? null : _security;
      final outcome = await ref
          .read(settingsPasskeysProvider)
          .add(
            // An encrypted account's new passkey opens the data too (its PRF wraps the data key).
            prf: security == null
                ? null
                : PasskeyPrfUse(
                    explainSecondTouch: () => toasts.say(l10n.settingsPasskeysSecondTouch),
                    keep: security.addPasskeyWrap,
                    onNoPrf: () => withoutPrf = true,
                  ),
          );
      switch (outcome) {
        case PasskeyOutcome.added:
          // An encrypted account's passkey that opens nothing: said at once, as text that stays.
          if (withoutPrf) {
            if (mounted) setState(() => _addedWithoutPrf = true);
          } else {
            toasts.say(l10n.settingsPasskeysAdded);
          }
          ref.invalidate(settingsPasskeyListProvider);
          if (security != null) ref.invalidate(securitySnapshotProvider);
        case PasskeyOutcome.failed:
          toasts.say(l10n.settingsPasskeysAddFailed, error: true);
        case PasskeyOutcome.cancelled:
          break;
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(PasskeyItem item) async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    final removed = await ConfirmSheet.show(
      context,
      title: l10n.settingsPasskeysRemoveTitle,
      body: l10n.settingsPasskeysRemoveBody,
      confirmLabel: l10n.settingsPasskeysRemoveConfirm,
      confirmKey: const Key('settings.passkeys.remove.confirm'),
      onConfirm: () async {
        try {
          await ref.read(settingsPasskeysProvider).remove(item.id);
        } on Object {
          // The sheet stays for another try, and says why.
          toasts.say(l10n.settingsPasskeysRemoveFailed, error: true);
          rethrow;
        }
        toasts.say(l10n.settingsPasskeysRemoved);
      },
    );
    if (removed) ref.invalidate(settingsPasskeyListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final list = ref.watch(settingsPasskeyListProvider);
    final canMake = ref.watch(_passkeysCanBeMadeProvider).value ?? true;
    final items = list.value;
    // Only an encrypted account (an open vault) says which passkeys open its data.
    final security = ref.watch(securityApiProvider);
    final wraps = security == null || widget.guest
        ? null
        : ref.watch(securitySnapshotProvider).value?.wraps;
    final rows = items == null ? null : passkeyRows(items, wraps);
    final addLabel = _adding ? l10n.settingsPasskeysAdding : l10n.settingsPasskeysAdd;
    final guest = widget.guest;

    final noteStyle = LkText.bodySm.copyWith(color: colors.inkMuted);
    Widget note(Widget child) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), child: child);
    final tint = colors.inkMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        SettingsGroup(
          key: const Key('settings.card.passkeys'),
          head: SettingsGroupHead(
            icon: LkIcon(LkIconName.fingerprint, size: 22, color: colors.brand),
            title: l10n.settingsPasskeysTitle,
            line: l10n.settingsPasskeysLine,
          ),
          rows: [
            if (list.hasError && items == null)
              note(CssParagraph(l10n.settingsPasskeysListFailed, style: noteStyle)),
            if (items != null && items.isEmpty)
              note(
                CssParagraph(
                  '${l10n.settingsPasskeysEmpty} ${l10n.settingsPasskeysLead}',
                  style: noteStyle,
                ),
              ),
            for (final row in rows ?? const <PasskeyRow>[]) ...[
              _passkeyRow(l10n, row, tint),
              if (row.unlocks == false && row.item.credentialId != null)
                _turnOnRow(l10n, row.item, tint),
              if (_noPrf == row.item.id)
                note(
                  CssParagraph(
                    l10n.settingsPasskeysTurnOnNoPrf,
                    style: LkText.bodySm.copyWith(color: colors.over),
                  ),
                ),
            ],
            if (!canMake)
              note(CssParagraph(l10n.settingsPasskeysUnsupported, style: noteStyle))
            else ...[
              SettingsRow(
                key: const Key('settings.passkeys.add'),
                icon: LkIcon(LkIconName.plus, size: 20, color: tint),
                title: addLabel,
                trailing: const RowNone(),
                onTap: _adding || guest ? null : () => unawaited(_add()),
              ),
              if (guest) note(CssParagraph(l10n.settingsPasskeysGuest, style: noteStyle)),
            ],
            if (_addedWithoutPrf)
              note(
                Semantics(
                  liveRegion: true,
                  container: true,
                  child: Text(
                    l10n.settingsPasskeysAddNoPrf,
                    key: const Key('settings.passkeys.addNoPrf'),
                    style: LkText.note.copyWith(color: colors.ink),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// One passkey: a device icon, its name (or "Huella"), "Desde el 2 oct" with " · sincronizada"
  /// when it syncs, and its trash button, which asks first.
  Widget _passkeyRow(AppLocalizations l10n, PasskeyRow row, Color tint) {
    final item = row.item;
    final day = passkeyDay(item.createdAt, l10n.localeName, widget.timeZone);
    final name = item.name;
    return SettingsRow(
      key: Key('settings.passkeys.row.${item.id}'),
      icon: LkIcon(deviceIconFor(name), size: 20, color: tint),
      title: name ?? l10n.settingsPasskeysDefaultName,
      line: item.synced
          ? '${l10n.settingsPasskeysCreated(day)} · ${l10n.settingsPasskeysSynced}'
          : l10n.settingsPasskeysCreated(day),
      trailing: RowTrash(
        buttonKey: Key('settings.passkeys.remove.${item.id}'),
        label: name == null
            ? l10n.settingsPasskeysRemoveLabel(day)
            : l10n.settingsPasskeysRemoveNamedLabel(name),
        onTap: () => unawaited(_remove(item)),
      ),
    );
  }

  /// A passkey of an encrypted account whose wrap is missing: a row that turns it on for the data.
  Widget _turnOnRow(AppLocalizations l10n, PasskeyItem item, Color tint) {
    final day = passkeyDay(item.createdAt, l10n.localeName, widget.timeZone);
    final name = item.name;
    return SettingsRow(
      key: Key('settings.passkeys.turnOn.${item.id}'),
      icon: LkIcon(LkIconName.key, size: 20, color: tint),
      title: name == null
          ? l10n.settingsPasskeysTurnOnLabel(day)
          : l10n.settingsPasskeysTurnOnNamedLabel(name),
      line: l10n.settingsPasskeysLocked,
      trailing: const RowChevron(),
      onTap: _turningOn != null ? null : () => unawaited(_turnOn(item)),
    );
  }
}
