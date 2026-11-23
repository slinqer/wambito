// "Captura automática" in Settings (spec sections 2.1 and 4): one switch row per source (its logo,
// "Activa" / "Apagada"), the state of Android's notification access and, when it is missing, how to
// grant it (the light `SettingsGroup`, spec 2026-11-22). Android only: where the
// `wambito/capture` channel does not exist the section is not drawn.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/stored_flag.dart';
import '../l10n/app_localizations.dart';
import '../settings/settings_parts.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_brand_logo.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import 'capture_platform.dart';
import 'how_capture_works.dart';

/// Whether the steps were already shown before a switch on (the first switch on shows them, once).
class AutoCaptureExplained extends StoredFlag {
  @override
  FlagStore get store => ref.read(flagStoreProvider('setting.capture.explained'));

  @override
  bool get initial => false;
}

final autoCaptureExplainedProvider = NotifierProvider<AutoCaptureExplained, bool>(
  AutoCaptureExplained.new,
);

class AutoCaptureSection extends ConsumerStatefulWidget {
  const AutoCaptureSection({super.key});

  @override
  ConsumerState<AutoCaptureSection> createState() => _AutoCaptureSectionState();
}

class _AutoCaptureSectionState extends ConsumerState<AutoCaptureSection>
    with WidgetsBindingObserver {
  AutoCaptureStatus? _status;

  /// The person tried to grant access from here (the "¿No te deja?" link shows after that).
  bool _tried = false;

  AutoCapturePlatform get _platform => ref.read(autoCapturePlatformProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final status = await _platform.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _openAccess() async {
    _tried = true;
    await _platform.openAccessSettings();
    if (mounted) setState(() {});
  }

  Future<void> _toggle(CaptureSource source, bool on) async {
    if (on) {
      final explained = ref.read(autoCaptureExplainedProvider.notifier);
      await explained.ready;
      if (!mounted) return;
      if (!ref.read(autoCaptureExplainedProvider)) {
        final go = await showHowCaptureWorks(context, askAccess: true);
        if (!go || !mounted) return;
        await explained.set(true);
      }
    }
    await _platform.setSource(source.wire, on);
    await _refresh();
    if (on && _status?.access == false) await _openAccess();
  }

  Future<void> _showSteps() async {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    await LkSheet.show<void>(
      context,
      title: l10n.autoCaptureStepsTitle,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: WambitoTokens.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space4,
            children: [
              CssParagraph(l10n.autoCaptureSteps, style: LkText.body.copyWith(color: colors.ink)),
              PressButton.text(
                l10n.autoCaptureOpenInfo,
                key: const Key('autoCapture.openInfo'),
                onPressed: () => unawaited(_platform.openAppInfo()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final tint = colors.inkMuted;
    final missing = status.anyOn && !status.access;
    return SettingsGroup(
      key: const Key('settings.card.autoCapture'),
      head: SettingsGroupHead(
        icon: LkIcon(LkIconName.wand, size: 22, color: colors.brand),
        title: l10n.autoCaptureTitle,
        line: l10n.autoCaptureLead,
      ),
      rows: [
        for (final source in status.offered)
          SettingsRow(
            key: Key('autoCapture.${source.wire}'),
            icon: switch (source.brand) {
              final brand? => LkBrandLogo(brand, size: 20, color: tint),
              null => LkIcon(LkIconName.coin, size: 20, color: tint),
            },
            title: source.label,
            line: status.isOn(source) ? l10n.autoCaptureActive : l10n.autoCaptureOff,
            trailing: RowSwitch(
              value: status.isOn(source),
              onChanged: (on) => unawaited(_toggle(source, on)),
            ),
          ),
        if (missing) ...[
          SettingsRow(
            key: const Key('autoCapture.missing'),
            icon: LkIcon(LkIconName.info, size: 20, color: colors.over),
            title: l10n.autoCaptureMissing,
            danger: true,
            trailing: const RowNone(),
          ),
          SettingsRow(
            key: const Key('autoCapture.grant'),
            icon: LkIcon(LkIconName.plus, size: 20, color: tint),
            title: l10n.autoCaptureGrant,
            trailing: const RowChevron(),
            onTap: () => unawaited(_openAccess()),
          ),
        ],
        if (missing && _tried)
          SettingsRow(
            key: const Key('autoCapture.stuck'),
            icon: LkIcon(LkIconName.info, size: 20, color: tint),
            title: l10n.autoCaptureStuck,
            trailing: const RowChevron(),
            onTap: () => unawaited(_showSteps()),
          ),
        // Under the apps it reads: what they do, step by step.
        SettingsRow(
          key: const Key('autoCapture.how'),
          icon: LkIcon(LkIconName.info, size: 20, color: tint),
          title: l10n.autoCaptureHowLink,
          line: l10n.autoCaptureHowLine,
          trailing: const RowChevron(),
          onTap: () => unawaited(showHowCaptureWorks(context, askAccess: false)),
        ),
      ],
    );
  }
}
