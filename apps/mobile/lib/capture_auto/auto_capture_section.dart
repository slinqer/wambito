// "Captura automática" in Settings (spec sections 2.1 and 4): one switch row per source (its logo,
// "Activa" / "Apagada"), the state of Android's notification access and, when it is missing, how to
// grant it (the light `SettingsGroup`, spec 2026-11-22). On the iPhone (spec
// 2026-11-22-ios-wallet-capture-design.md, 3.4) the one row is Apple Pay ("Configurada" / "Sin
// configurar"), with "Configurar en Atajos" and "Probar". Where the `wambito/capture` channel does
// not exist the section is not drawn.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/stored_flag.dart';
import '../l10n/app_localizations.dart';
import '../notices/notice_platform.dart';
import '../settings/settings_parts.dart';
import '../settings/url_opener.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_brand_logo.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import 'capture_platform.dart';
import 'how_capture_works.dart';
import 'wallet_setup.dart';

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

  /// iPhone: Apple Pay was switched off here (the row to remove the automation shows).
  bool _turnedOff = false;

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
    final iosMajor = _status?.iosMajor;
    final shortcutUrl = ref.read(walletShortcutUrlProvider);
    final install = iosMajor != null && walletInstallable(iosMajor, shortcutUrl);
    var explainedNow = false;
    if (on) {
      final explained = ref.read(autoCaptureExplainedProvider.notifier);
      await explained.ready;
      if (!mounted) return;
      if (!ref.read(autoCaptureExplainedProvider)) {
        final go = await showHowCaptureWorks(
          context,
          askAccess: true,
          iphone: iosMajor != null,
          installShortcut: install,
        );
        if (!go || !mounted) return;
        await explained.set(true);
        explainedNow = true;
      }
    }
    await _platform.setSource(source.wire, on);
    _turnedOff = !on && iosMajor != null;
    await _refresh();
    if (iosMajor != null) {
      // The iPhone has no access to grant: the automation is what makes it work.
      if (!explainedNow || !mounted) return;
      if (install) {
        // Straight to Shortcuts; what is left waits here for the return.
        unawaited(ref.read(urlOpenerProvider).open(Uri.parse(shortcutUrl)));
        await showWalletFinish(context);
      } else {
        await showWalletSetup(context, iosMajor: iosMajor, shortcutUrl: shortcutUrl);
      }
      return;
    }
    if (on && _status?.access == false) await _openAccess();
  }

  /// "Probar": the notification a payment brings, with an invented one; nothing is saved.
  Future<void> _test() async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    // Asked first, so the sample shows the first time too.
    final notices = await ref.read(noticePlatformProvider).permission();
    final allowed =
        notices == NoticePermission.granted ||
        (notices == NoticePermission.askable &&
            await ref.read(noticePlatformProvider).requestPermission());
    final posted = await _platform.testCapture(
      l10n.autoCaptureTestNotice(l10n.autoCaptureTestMerchant, l10n.autoCaptureHowOtherExpenses),
    );
    if (!mounted) return;
    toasts.say(posted && allowed ? l10n.autoCaptureTestSent : l10n.autoCaptureTestNoNotices);
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
    final iosMajor = status.iosMajor;
    return SettingsGroup(
      key: const Key('settings.card.autoCapture'),
      head: SettingsGroupHead(
        icon: LkIcon(LkIconName.wand, size: 22, color: colors.brand),
        title: l10n.autoCaptureTitle,
        line: iosMajor != null ? l10n.autoCaptureIosLead : l10n.autoCaptureLead,
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
            line: switch ((status.isOn(source), iosMajor != null)) {
              (false, _) => l10n.autoCaptureOff,
              (true, false) => l10n.autoCaptureActive,
              (true, true) =>
                status.configured ? l10n.autoCaptureConfigured : l10n.autoCaptureNotConfigured,
            },
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
        if (iosMajor != null && status.anyOn) ...[
          SettingsRow(
            key: const Key('autoCapture.setup'),
            icon: LkIcon(LkIconName.wand, size: 20, color: tint),
            title: l10n.autoCaptureSetup,
            line: l10n.autoCaptureSetupLine,
            trailing: const RowChevron(),
            onTap: () => unawaited(
              showWalletSetup(
                context,
                iosMajor: iosMajor,
                shortcutUrl: ref.read(walletShortcutUrlProvider),
              ),
            ),
          ),
          SettingsRow(
            key: const Key('autoCapture.test'),
            icon: LkIcon(LkIconName.bell, size: 20, color: tint),
            title: l10n.autoCaptureTest,
            line: l10n.autoCaptureTestLine,
            trailing: const RowChevron(),
            onTap: () => unawaited(_test()),
          ),
        ],
        if (iosMajor != null && !status.anyOn && _turnedOff)
          SettingsRow(
            key: const Key('autoCapture.remove'),
            icon: LkIcon(LkIconName.info, size: 20, color: tint),
            title: l10n.autoCaptureRemove,
            trailing: const RowChevron(),
            onTap: () => unawaited(_platform.openShortcuts()),
          ),
        // Under the apps it reads: what they do, step by step.
        SettingsRow(
          key: const Key('autoCapture.how'),
          icon: LkIcon(LkIconName.info, size: 20, color: tint),
          title: l10n.autoCaptureHowLink,
          line: l10n.autoCaptureHowLine,
          trailing: const RowChevron(),
          onTap: () =>
              unawaited(showHowCaptureWorks(context, askAccess: false, iphone: iosMajor != null)),
        ),
      ],
    );
  }
}
