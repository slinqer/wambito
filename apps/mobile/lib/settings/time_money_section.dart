// "Hora y moneda" of the web's Settings (apps/web/app/features/settings/TimeAndMoneySection.tsx):
// the profile's time zone, with a sheet to search the zones by city or country, and the currency
// while it can still change. The rules (the currencies, the zones, the search) are the welcome's and
// settings_model.dart's; nothing here is decided twice.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/device.dart';
import '../api/gen/wambito_api.dart';
import '../home/home_controller.dart';
import '../home/home_repository.dart';
import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../profile/currency.dart';
import '../recurring/recurring_repository.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/native_radio.dart';
import '../ui/press_button.dart';
import '../ui/pressable.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import '../ui/web_text_field.dart';
import 'profile_settings.dart';
import 'settings_model.dart';
import 'settings_parts.dart';

/// The time zone, and the currency while it can still change.
class TimeAndMoneySection extends StatelessWidget {
  const TimeAndMoneySection({super.key, required this.profile});

  final HomeProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsGroup(
      key: const Key('settings.card.timeMoney'),
      label: l10n.settingsTimeAndMoney,
      rows: [
        _TimeZoneSetting(zone: profile.timezone),
        _CurrencySetting(currency: profile.currency),
      ],
    );
  }
}

/// How many zones a search lists at once; typing narrows it.
const zonesShown = 40;

// -- the time zone ----------------------------------------------------------------------------------

/// The profile's time zone (`America/Bogota` shown as "Bogota" on its row); the row opens a sheet to
/// search the zones by city or country, with the hint on what the zone is for. Picking one saves it,
/// and everything that reads "today" follows.
class _TimeZoneSetting extends ConsumerWidget {
  const _TimeZoneSetting({required this.zone});

  final String zone;

  Future<void> _change(BuildContext context) async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    final saved = await LkSheet.show<String>(
      context,
      title: l10n.settingsTimezoneSheetTitle,
      children: [_ZoneSheet(zone: zone, toasts: toasts)],
    );
    if (saved != null) toasts.say(l10n.settingsTimezoneSaved(zoneCity(saved)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SettingsRow(
      key: const Key('settings.timezone.change'),
      icon: LkIcon(LkIconName.clock, size: 20, color: context.lkColors.inkMuted),
      title: l10n.settingsTimezoneLabel,
      trailing: RowChevron(value: zoneCity(zone)),
      onTap: () => unawaited(_change(context)),
    );
  }
}

/// The sheet that searches the zones: the search field, the phone's own zone while nothing is typed,
/// and up to [zonesShown] zones by city, or what was not found.
class _ZoneSheet extends ConsumerStatefulWidget {
  const _ZoneSheet({required this.zone, required this.toasts});

  final String zone;

  /// Where a failure is said: the screen's, which shows in the sheet while it is open.
  final ToastController toasts;

  @override
  ConsumerState<_ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends ConsumerState<_ZoneSheet> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  var _busy = false;

  late final List<String> _supported = pickableTimeZones();

  /// The profile's zone in the list's spelling: the welcome may have saved the phone's (IANA's).
  late final String _current = canonicalZone(widget.zone);
  late final List<String> _zones = _supported.contains(_current)
      ? _supported
      : [widget.zone, ..._supported];
  late final ZoneSearchIndex _index = zoneSearchIndex(_zones);

  @override
  void initState() {
    super.initState();
    _query.addListener(_typed);
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed() => setState(() {});

  Future<void> _choose(String next) async {
    if (_busy) return;
    if (canonicalZone(next) == _current) {
      Navigator.of(context).pop();
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(profileActionsProvider).setTimezone(next);
    } on HomeFailure catch (failure) {
      widget.toasts.say(profileFailureMessage(l10n, failure), error: true);
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (mounted) Navigator.of(context).pop(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final query = _query.text;
    final found = searchZones(_zones, query, zonesShown, _index);
    // The phone reports IANA's spelling; the list, the profile and the API have the web's.
    final device = canonicalZone(ref.watch(deviceHintsProvider).timezone);
    final offerDevice = device != _current && _supported.contains(device) ? device : null;
    final mutedStyle = LkText.copy.copyWith(color: colors.inkMuted, fontSize: 15);
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space3,
        children: [
          CssParagraph(l10n.settingsTimezoneHint, style: mutedStyle),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space1,
            children: [
              Text(l10n.settingsTimezoneSearch, style: LkText.bodySm.copyWith(color: colors.ink)),
              WebTextField(
                controller: _query,
                focusNode: _focus,
                fieldKey: const Key('settings.timezone.search'),
                label: l10n.settingsTimezoneSearch,
                placeholder: l10n.settingsTimezonePlaceholder,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.search,
                inputMinHeight: 36,
              ),
            ],
          ),
          if (offerDevice != null && query.isEmpty)
            PressButton.text(
              l10n.settingsTimezoneUseDevice(zoneCity(offerDevice)),
              key: const Key('settings.timezone.useDevice'),
              tone: PressTone.secondary,
              onPressed: _busy ? null : () => unawaited(_choose(offerDevice)),
            ),
          if (found.matches.isEmpty)
            Semantics(
              liveRegion: true,
              container: true,
              child: CssParagraph(l10n.settingsTimezoneNoResults(query.trim()), style: mutedStyle),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WambitoTokens.space2,
              children: [
                for (final candidate in found.matches)
                  _ZoneOption(
                    key: Key('settings.timezone.option.$candidate'),
                    zone: candidate,
                    current: canonicalZone(candidate) == _current,
                    disabled: _busy,
                    onPick: () => unawaited(_choose(candidate)),
                  ),
              ],
            ),
          if (found.more > 0)
            CssParagraph(
              l10n.settingsTimezoneMore(found.more),
              style: LkText.fieldLabel.copyWith(color: colors.inkMuted),
            ),
        ],
      ),
    );
  }
}

/// One zone of the list: `lk-rowcard lk-zone`, a button as wide as the sheet, 44px at least, with the
/// city, the region and the offset, and "Actual" on the one in use.
class _ZoneOption extends ConsumerWidget {
  const _ZoneOption({
    super.key,
    required this.zone,
    required this.current,
    required this.disabled,
    required this.onPick,
  });

  final String zone;
  final bool current;
  final bool disabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final now = ref.read(clockProvider)();
    final region = [
      zoneRegion(zone),
      zoneOffset(zone, l10n.localeName, now),
    ].where((part) => part.isNotEmpty).join(' · ');
    return Pressable(
      onPressed: disabled ? null : onPick,
      label: '${zoneCity(zone)}, $region${current ? ', ${l10n.settingsTimezoneCurrent}' : ''}',
      selected: current,
      builder: (context, state) {
        final radius = LkSurface.radius(LkRadius.lg);
        return PressSurface(
          minSize: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: LkSurface.rowCard(lk),
          ringRadius: state.focusVisible ? radius : null,
          ringColor: colors.focus,
          child: ExcludeSemantics(
            child: SizedBox(
              width: double.infinity,
              child: Row(
                spacing: WambitoTokens.space2,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CssBlinkLines(
                          style: LkText.body,
                          child: Text(
                            zoneCity(zone),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LkText.body.copyWith(color: colors.ink),
                          ),
                        ),
                        if (region.isNotEmpty)
                          CssBlinkLines(
                            style: LkText.fieldLabel,
                            child: Text(
                              region,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LkText.fieldLabel.copyWith(color: colors.inkMuted),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (current) _SoonPill(l10n.settingsTimezoneCurrent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `.lk-soon`: a small pill that marks something ("Actual", "Pronto"): 10px, upper case, muted, with
/// a 1.5px stroke.
class _SoonPill extends StatelessWidget {
  const _SoonPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: LkSurface.radius(LkRadius.pill),
        border: Border.all(color: colors.stroke, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        child: Text(
          LkText.upperCase(label),
          style: TextStyle(
            fontFamily: LkText.textFamily,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.06 * 10,
            height: 1.5,
            leadingDistribution: TextLeadingDistribution.even,
            color: colors.inkMuted,
          ),
        ),
      ),
    );
  }
}

// -- the currency -----------------------------------------------------------------------------------

/// What 50 lukas (or 50 dollars, 50 euros) look like in each currency, as amounts are shown.
const _example = {'COP': 5000000, 'USD': 5000, 'EUR': 5000};

// No automatic retry: a list that cannot be read counts as known (`known` below), and the server
// has the last word on the currency anyway.
final _hasTransactionsProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(homeRepositoryProvider).hasTransactions(),
  retry: (_, _) => null,
);

final _recurrencesProvider = FutureProvider.autoDispose<List<Recurrence>>(
  (ref) => ref.watch(recurringRepositoryProvider).list(),
  retry: (_, _) => null,
);

/// The currency's row: the code as its value; it opens [_CurrencySheet]. The row watches what the
/// sheet reads, so the answers are in by the time it opens.
class _CurrencySetting extends ConsumerWidget {
  const _CurrencySetting({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref
      ..watch(_hasTransactionsProvider)
      ..watch(_recurrencesProvider);
    return SettingsRow(
      key: const Key('settings.currency.row'),
      icon: LkIcon(LkIconName.coin, size: 20, color: context.lkColors.inkMuted),
      title: l10n.settingsCurrencyLabel,
      trailing: RowChevron(value: currency),
      onTap: () => unawaited(
        LkSheet.show<void>(
          context,
          title: l10n.settingsCurrencyLabel,
          children: [_CurrencySheet(currency: currency, toasts: ToastHost.of(context))],
        ),
      ),
    );
  }
}

/// The account's currency, while it can still change: one radio per supported currency with an
/// example amount, shown while this screen sees no transactions and no recurring payments. The
/// server has the last word, since it also counts deleted transactions, which the list here never
/// returns: a 409 `currency_locked` turns the choice into the same short line as an account that
/// visibly has movements. Another pick is ignored until the first one is answered.
class _CurrencySheet extends ConsumerStatefulWidget {
  const _CurrencySheet({required this.currency, required this.toasts});

  final String currency;

  /// Where a failure or the saved line is said: the screen's, which shows over the sheet.
  final ToastController toasts;

  @override
  ConsumerState<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends ConsumerState<_CurrencySheet> {
  var _lockedByServer = false;
  var _busy = false;

  Future<void> _choose(String next) async {
    if (_busy || next == widget.currency) return;
    final l10n = AppLocalizations.of(context);
    final toasts = widget.toasts;
    setState(() => _busy = true);
    try {
      await ref.read(profileActionsProvider).setCurrency(next);
    } on HomeFailure catch (failure) {
      if (failure.code == 'currency_locked') {
        if (mounted) setState(() => _lockedByServer = true);
      } else {
        toasts.say(profileFailureMessage(l10n, failure), error: true);
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    toasts.say(l10n.settingsCurrencySaved(next));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WambitoTokens.space3),
    child: _content(context),
  );

  Widget _content(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final transactions = ref.watch(_hasTransactionsProvider);
    final recurrences = ref.watch(_recurrencesProvider);
    final known =
        (transactions.hasValue || transactions.hasError) &&
        (recurrences.hasValue || recurrences.hasError);
    final locked =
        _lockedByServer ||
        transactions.value == true ||
        (recurrences.value?.isNotEmpty ?? false) ||
        !isSupportedCurrency(widget.currency);

    if (known && locked) {
      return CssParagraph(
        l10n.settingsCurrencyLocked(widget.currency),
        key: const Key('settings.currency.locked'),
        style: LkText.bodySm.copyWith(color: colors.inkMuted),
      );
    }

    final locale = l10n.localeName;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.radioGroup,
      label: l10n.settingsCurrencyLabel,
      child: Column(
        key: const Key('settings.currency.group'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space2,
        children: [
          // The legend: the group is named by the label, and the hint is read after it.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space1,
            children: [
              ExcludeSemantics(
                child: CssParagraph(
                  l10n.settingsCurrencyLabel,
                  style: LkText.body.copyWith(color: colors.ink),
                ),
              ),
              CssParagraph(
                l10n.settingsCurrencyHint,
                style: LkText.fieldLabel.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
          for (final code in supportedCurrencies)
            _CurrencyOption(
              key: Key('settings.currency.$code'),
              code: code,
              name: currencyName(code, locale),
              example: _exampleText(code, locale),
              selected: widget.currency == code,
              enabled: known,
              onSelect: () => unawaited(_choose(code)),
            ),
        ],
      ),
    );
  }

  static String _exampleText(String code, String locale) {
    final cents = _example[code]!;
    final example = formatMoney(cents, code, locale);
    final hint = lukasHint(cents, locale, currency: code);
    return hint == null ? example : '$example $hint';
  }
}

/// `flex min-h-11 items-center gap-3 rounded-lg border-2 border-stroke bg-surface-row px-4 py-2
/// shadow-edge-sm has-checked:border-brand-glow has-disabled:opacity-60 has-focus-visible:outline-3`:
/// a native radio (20px, `accent-brand`), the currency's name over its example amount, and its code.
class _CurrencyOption extends StatelessWidget {
  const _CurrencyOption({
    super.key,
    required this.code,
    required this.name,
    required this.example,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final String code;
  final String name;
  final String example;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final radius = LkSurface.radius(LkRadius.lg);
    const tabular = [FontFeature.tabularFigures()];
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Pressable(
        onPressed: enabled ? onSelect : null,
        label: '$name $example $code',
        checked: selected,
        builder: (context, state) => PressSurface(
          decoration: BoxDecoration(
            color: colors.surfaceRow,
            borderRadius: radius,
            border: Border.all(color: selected ? colors.brandGlow : colors.stroke, width: 2),
            boxShadow: LkSurface.edgeShadow(lk, LkEdge.sm),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WambitoTokens.space4,
            vertical: WambitoTokens.space2,
          ),
          ringRadius: state.focusVisible ? radius : null,
          ringColor: colors.focus,
          child: ExcludeSemantics(
            child: Row(
              spacing: WambitoTokens.space3,
              children: [
                NativeRadio(checked: selected, accent: colors.brand),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: LkText.copy.copyWith(color: colors.ink)),
                      // 13px at 1.5 is 19.5px a line in CSS.
                      CssBlinkLines(
                        style: LkText.fieldLabel,
                        child: Text(
                          example,
                          style: LkText.fieldLabel.copyWith(
                            color: colors.inkMuted,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  code,
                  style: LkText.copy.copyWith(color: colors.inkMuted, fontFeatures: tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
