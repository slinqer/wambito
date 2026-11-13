// "Captura automática" in Settings (spec sections 2.1 and 4): one switch per source, the state of
// Android's notification access and, when it is missing, how to grant it. Android only: where the
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
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/press_link.dart';
import '../ui/sheet.dart';
import '../vault/preview.dart';
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
    // An encrypted (`preview`) account's finances never leave the phone, and capture sends them to
    // the server: the switches wait for encryption.
    if (ref.watch(isPreviewProvider)) {
      return SettingsSection(
        key: const Key('settings.card.autoCapture'),
        title: l10n.autoCaptureTitle,
        children: const [ComingSoonNotice(key: Key('autoCapture.comingSoon'))],
      );
    }
    final missing = status.anyOn && !status.access;
    return SettingsSection(
      key: const Key('settings.card.autoCapture'),
      title: l10n.autoCaptureTitle,
      lead: l10n.autoCaptureLead,
      children: [
        for (final source in CaptureSource.values)
          SettingSwitch(
            key: Key('autoCapture.${source.wire}'),
            label: source.label,
            value: status.isOn(source),
            onChanged: (on) => unawaited(_toggle(source, on)),
          ),
        if (missing)
          Column(
            key: const Key('autoCapture.missing'),
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space2,
            children: [
              CssParagraph(
                l10n.autoCaptureMissing,
                style: LkText.body.copyWith(color: colors.over),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: PressButton.text(
                  l10n.autoCaptureGrant,
                  key: const Key('autoCapture.grant'),
                  tone: PressTone.secondary,
                  onPressed: () => unawaited(_openAccess()),
                ),
              ),
              if (_tried)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PressLink.text(
                    l10n.autoCaptureStuck,
                    key: const Key('autoCapture.stuck'),
                    tone: PressTone.secondary,
                    onPressed: () => unawaited(_showSteps()),
                  ),
                ),
            ],
          )
        else if (status.anyOn)
          CssParagraph(
            l10n.autoCaptureActive,
            key: const Key('autoCapture.active'),
            style: LkText.bodySm.copyWith(color: colors.inkMuted),
          ),
        // Under the apps it reads: what they do, step by step.
        Align(
          alignment: Alignment.centerLeft,
          child: PressLink.text(
            l10n.autoCaptureHowLink,
            key: const Key('autoCapture.how'),
            tone: PressTone.secondary,
            onPressed: () => unawaited(showHowCaptureWorks(context, askAccess: false)),
          ),
        ),
      ],
    );
  }
}
