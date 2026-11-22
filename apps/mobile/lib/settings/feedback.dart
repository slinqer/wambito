// "Comentarios e ideas" in Settings: the web's apps/web/app/features/settings/FeedbackSection.tsx and
// feedback.ts. For now an email to the founder: a button that opens the person's email app with a
// message ready to write, and, where no email app answers, the address with a button to copy it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/press_link.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import 'settings_parts.dart';
import 'url_opener.dart';

/// Where comments and ideas go (the founder's choice, 2026-10-24). Here and nowhere else in the app;
/// the web has its own copy of it (apps/web/app/features/settings/feedback.ts).
const feedbackEmail = 'hola@wambito.com';

/// The `mailto:` link for a message to [feedbackEmail]: the subject and the body percent-encoded (a
/// `&`, `=`, `#` or `?` in either must not end the query, nor start another header). The web builds
/// the same string.
String feedbackMailto({required String subject, required String body}) =>
    'mailto:$feedbackEmail?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';

/// The version the app was built as (`versionName`), asked of the phone (MainActivity.kt); "dev" where
/// it cannot be known (tests, a platform with no Android side).
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    return await const MethodChannel('wambito/device').invokeMethod<String>('appVersion') ?? 'dev';
  } on PlatformException {
    return 'dev';
  } on MissingPluginException {
    return 'dev';
  }
});

/// The row in Más: "Comentarios e ideas", whose sheet holds today's form: what it is for, the
/// button, and the address in writing under it (the web writes it out too, for a browser with no
/// email app).
class FeedbackSection extends ConsumerWidget {
  const FeedbackSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SettingsRow(
      key: const Key('settings.card.feedback'),
      icon: LkIcon(LkIconName.chat, size: 20, color: context.lkColors.inkMuted),
      title: l10n.settingsFeedbackTitle,
      line: l10n.settingsFeedbackRowLine,
      trailing: const RowChevron(),
      onTap: () => unawaited(_open(context, ref)),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final write = await LkSheet.show<bool>(
      context,
      title: l10n.settingsFeedbackTitle,
      children: [const _FeedbackForm()],
    );
    if (write == true && context.mounted) await _write(context, ref);
  }

  /// Opens the email app with the message: the subject in the person's language and a body of only
  /// the version and the language (after two blank lines to write above). Nothing of the account.
  Future<void> _write(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    String version;
    try {
      version = await ref.read(appVersionProvider.future);
    } on Object {
      version = 'dev';
    }
    final link = feedbackMailto(
      subject: l10n.settingsFeedbackMailSubject,
      body: '\n\n${l10n.settingsFeedbackMailBody(version, l10n.localeName)}',
    );
    final opened = await ref.read(urlOpenerProvider).open(Uri.parse(link));
    if (!opened && context.mounted) await _noEmailApp(context);
  }

  /// No email app answered: the address, to copy.
  Future<void> _noEmailApp(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    final copied = await LkSheet.show<bool>(
      context,
      title: l10n.settingsFeedbackNoAppTitle,
      children: [const _NoEmailApp()],
    );
    if (copied == true) toasts.say(l10n.settingsFeedbackCopied(feedbackEmail));
  }
}

class _NoEmailApp extends StatelessWidget {
  const _NoEmailApp();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Padding(
      key: const Key('settings.feedback.sheet'),
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space4,
        children: [
          CssParagraph(
            l10n.settingsFeedbackNoAppBody(feedbackEmail),
            style: LkText.body.copyWith(color: colors.ink),
          ),
          PressButton.text(
            l10n.settingsFeedbackCopy,
            key: const Key('settings.feedback.copy'),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await Clipboard.setData(const ClipboardData(text: feedbackEmail));
              navigator.pop(true);
            },
          ),
        ],
      ),
    );
  }
}

class _FeedbackForm extends StatelessWidget {
  const _FeedbackForm();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WambitoTokens.space3,
        children: [
          CssParagraph(l10n.settingsFeedbackLead, style: LkText.body.copyWith(color: colors.ink)),
          PressLink.text(
            l10n.settingsFeedbackAction,
            key: const Key('settings.feedback'),
            tone: PressTone.secondary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          CssParagraph(
            l10n.settingsFeedbackAddress(feedbackEmail),
            style: LkText.bodySm.copyWith(color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}
