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
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/css_text.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/offset_underline.dart';
import '../ui/pressable.dart' show PressSurface;
import '../ui/press_button.dart';
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
    final mutedSm = LkText.bodySm.copyWith(color: colors.inkMuted);
    final items = list.value;
    // Only an encrypted account (an open vault) says which passkeys open its data.
    final security = ref.watch(securityApiProvider);
    final wraps = security == null || widget.guest
        ? null
        : ref.watch(securitySnapshotProvider).value?.wraps;
    final rows = items == null ? null : passkeyRows(items, wraps);
    final addLabel = _adding ? l10n.settingsPasskeysAdding : l10n.settingsPasskeysAdd;
    final guest = widget.guest;

    return SettingsSection(
      key: const Key('settings.card.passkeys'),
      title: l10n.settingsPasskeysTitle,
      lead: l10n.settingsPasskeysLead,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            if (list.hasError && items == null)
              CssParagraph(l10n.settingsPasskeysListFailed, style: mutedSm),
            if (items != null && items.isEmpty)
              CssParagraph(
                l10n.settingsPasskeysEmpty,
                style: LkText.bodySm.copyWith(color: colors.ink),
              ),
            if (rows != null && rows.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WambitoTokens.space2,
                children: [
                  for (final row in rows)
                    _PasskeyRow(
                      item: row.item,
                      unlocks: row.unlocks,
                      day: passkeyDay(row.item.createdAt, l10n.localeName, widget.timeZone),
                      busy: _turningOn != null,
                      noPrf: _noPrf == row.item.id,
                      onRemove: () => unawaited(_remove(row.item)),
                      onTurnOn: () => unawaited(_turnOn(row.item)),
                    ),
                ],
              ),
          ],
        ),
        if (!canMake)
          CssParagraph(l10n.settingsPasskeysUnsupported, style: mutedSm)
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: PressButton(
              key: const Key('settings.passkeys.add'),
              tone: PressTone.secondary,
              onPressed: _adding || guest ? null : () => unawaited(_add()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: WambitoTokens.space2,
                children: [
                  const FingerprintIcon(),
                  Flexible(child: Text(LkText.upperCase(addLabel))),
                ],
              ),
            ),
          ),
          if (guest) CssParagraph(l10n.settingsPasskeysGuest, style: mutedSm),
        ],
        if (_addedWithoutPrf)
          SizedBox(
            width: double.infinity,
            child: Semantics(
              liveRegion: true,
              container: true,
              child: DecoratedBox(
                decoration: LkSurface.rowCard(context.lk),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    l10n.settingsPasskeysAddNoPrf,
                    key: const Key('settings.passkeys.addNoPrf'),
                    style: LkText.note.copyWith(color: colors.ink),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One passkey: `lk-rowcard justify-between`, the fingerprint in `brand-glow`, its name (or
/// "Huella") over "Creada el…" and "Sincronizada", and its "Eliminar".
class _PasskeyRow extends StatelessWidget {
  const _PasskeyRow({
    required this.item,
    required this.unlocks,
    required this.day,
    required this.busy,
    required this.noPrf,
    required this.onRemove,
    required this.onTurnOn,
  });

  final PasskeyItem item;

  /// Whether a passkey wrap opens the data with it; null for a plain account (nothing is said).
  final bool? unlocks;
  final String day;

  /// A "Turn on" is running: the others wait.
  final bool busy;

  /// This passkey's provider gives no PRF: it cannot open the data.
  final bool noPrf;
  final VoidCallback onRemove;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final name = item.name;
    final removeLabel = name == null
        ? l10n.settingsPasskeysRemoveLabel(day)
        : l10n.settingsPasskeysRemoveNamedLabel(name, day);
    final muted = LkText.fieldLabel.copyWith(color: colors.inkMuted);
    return PressSurface(
      minSize: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: LkSurface.rowCard(lk),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            Row(
              spacing: 10,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    spacing: WambitoTokens.space3,
                    children: [
                      DefaultTextStyle.merge(
                        style: TextStyle(color: colors.brandGlow),
                        child: const FingerprintIcon(),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CssBlinkLines(
                              style: LkText.body,
                              child: Text(
                                name ?? l10n.settingsPasskeysDefaultName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: LkText.body.copyWith(color: colors.ink),
                              ),
                            ),
                            Wrap(
                              spacing: WambitoTokens.space2,
                              children: [
                                CssBlinkLines(
                                  style: LkText.fieldLabel,
                                  child: Text(l10n.settingsPasskeysCreated(day), style: muted),
                                ),
                                if (item.synced)
                                  CssBlinkLines(
                                    style: LkText.fieldLabel,
                                    child: Text(l10n.settingsPasskeysSynced, style: muted),
                                  ),
                                if (unlocks == true)
                                  CssBlinkLines(
                                    style: LkText.fieldLabel,
                                    child: Text(l10n.settingsPasskeysUnlocks, style: muted),
                                  ),
                                if (unlocks == false)
                                  CssBlinkLines(
                                    style: LkText.fieldLabel,
                                    child: Text(
                                      l10n.settingsPasskeysLocked,
                                      style: muted.copyWith(
                                        color: colors.ink,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (unlocks == false && item.credentialId != null)
                  PressButton.text(
                    l10n.settingsPasskeysTurnOn,
                    key: Key('settings.passkeys.turnOn.${item.id}'),
                    tone: PressTone.secondary,
                    size: PressSize.sm,
                    semanticLabel: name == null
                        ? l10n.settingsPasskeysTurnOnLabel(day)
                        : l10n.settingsPasskeysTurnOnNamedLabel(name),
                    onPressed: busy ? null : onTurnOn,
                  ),
                PressButton(
                  key: Key('settings.passkeys.remove.${item.id}'),
                  tone: PressTone.ghost,
                  size: PressSize.sm,
                  semanticLabel: removeLabel,
                  onPressed: onRemove,
                  child: OffsetUnderline(LkText.upperCase(l10n.settingsPasskeysRemove)),
                ),
              ],
            ),
            if (noPrf)
              CssParagraph(
                l10n.settingsPasskeysTurnOnNoPrf,
                style: LkText.bodySm.copyWith(color: colors.over),
              ),
          ],
        ),
      ),
    );
  }
}
