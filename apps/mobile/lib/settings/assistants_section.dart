// "Conecta tu asistente" in Settings (spec §6.2): the MCP's address with a button to copy it, where
// Claude and ChatGPT take it, two things to ask, and the assistants the person let in, each with
// when it was connected, when it was last used and its own "Revocar" after asking. Connecting
// happens in the assistant and on the web's consent screen; the app only reads and revokes.
// A guest's account cannot be connected: they save their progress with an email first.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/server_url.dart';
import '../api/session.dart';
import '../home/home_repository.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/offset_underline.dart';
import '../ui/pressable.dart' show PressSurface;
import '../ui/press_button.dart';
import '../ui/toast.dart';
import '../vault/preview.dart';
import 'assistants_repository.dart';
import 'passkeys_section.dart' show passkeyDay;
import 'profile_settings.dart' show profileFailureMessage;
import 'settings_parts.dart';

/// The connected assistants, read when Settings opens; a revoked one leaves the list at once.
final settingsAssistantListProvider = FutureProvider.autoDispose<List<ConnectedAssistant>>(
  (ref) => ref.watch(assistantsRepositoryProvider).list(),
  // The card says it could not load them; opening Settings again asks again.
  retry: (_, _) => null,
);

class AssistantsSection extends ConsumerStatefulWidget {
  const AssistantsSection({super.key, required this.timeZone, required this.guest});

  /// The profile's zone: the dates are in it.
  final String timeZone;

  /// A guest sees how to connect, and that they save their progress first, instead of the list.
  final bool guest;

  @override
  ConsumerState<AssistantsSection> createState() => _AssistantsSectionState();
}

class _AssistantsSectionState extends ConsumerState<AssistantsSection> {
  /// Revoked here: gone from the list without reading it again.
  final _revoked = <String>{};

  Future<void> _copy(Uri url) async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    await Clipboard.setData(ClipboardData(text: url.toString()));
    toasts.say(l10n.settingsAssistantsCopied);
  }

  Future<void> _revoke(ConnectedAssistant item) async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    final revoked = await ConfirmSheet.show(
      context,
      title: l10n.settingsAssistantsRevokeTitle(item.name),
      body: l10n.settingsAssistantsRevokeBody,
      confirmLabel: l10n.settingsAssistantsRevokeConfirm,
      confirmKey: const Key('settings.assistants.revoke.confirm'),
      onConfirm: () async {
        try {
          await ref.read(assistantsRepositoryProvider).revoke(item.clientId);
        } on Object catch (error) {
          final failure = error is HomeFailure ? error : const HomeFailure(0);
          // The server no longer knows the session: signed out, as every other call ends it.
          if (failure.unauthorized) {
            unawaited(ref.read(sessionProvider.notifier).signOut(discardGuest: true));
          }
          // The sheet stays for another try, and says why.
          toasts.say(profileFailureMessage(l10n, failure), error: true);
          rethrow;
        }
        toasts.say(l10n.settingsAssistantsRevoked(item.name));
      },
    );
    if (revoked && mounted) setState(() => _revoked.add(item.clientId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final mutedSm = LkText.bodySm.copyWith(color: colors.inkMuted);
    final inkSm = LkText.bodySm.copyWith(color: colors.ink);
    // The assistants read the server's data, and an encrypted account's lives on the phone: no
    // address to connect to and no list (`GET /v1/me/assistants` is not asked).
    if (ref.watch(isPreviewProvider)) {
      return SettingsSection(
        key: const Key('settings.card.assistants'),
        title: l10n.settingsAssistantsTitle,
        children: const [ComingSoonNotice(key: Key('settings.assistants.comingSoon'))],
      );
    }
    final url = mcpUrl(ref.watch(serverUrlProvider));
    final guest = widget.guest;

    return SettingsSection(
      key: const Key('settings.card.assistants'),
      title: l10n.settingsAssistantsTitle,
      lead: l10n.settingsAssistantsLead,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            SettingLabel(label: l10n.settingsAssistantsUrl, hint: l10n.settingsAssistantsUrlHint),
            PressSurface(
              minSize: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: LkSurface.rowCard(lk),
              child: Row(
                spacing: 10,
                children: [
                  Expanded(
                    // Plain text: the button copies it (a SelectableText would also listen to the
                    // app's lifecycle, as every text field does).
                    child: Text(
                      url.toString(),
                      key: const Key('settings.assistants.url'),
                      style: LkText.body.copyWith(color: colors.ink),
                    ),
                  ),
                  PressButton(
                    key: const Key('settings.assistants.copy'),
                    tone: PressTone.ghost,
                    size: PressSize.sm,
                    semanticLabel: l10n.settingsAssistantsCopyLabel,
                    onPressed: () => unawaited(_copy(url)),
                    child: OffsetUnderline(LkText.upperCase(l10n.settingsAssistantsCopy)),
                  ),
                ],
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            CssParagraph(l10n.settingsAssistantsClaude, style: inkSm),
            CssParagraph(l10n.settingsAssistantsChatGpt, style: inkSm),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space1,
          children: [
            CssParagraph(l10n.settingsAssistantsExamples, style: mutedSm),
            CssParagraph(l10n.settingsAssistantsExampleAdd, style: inkSm),
            CssParagraph(l10n.settingsAssistantsExampleAsk, style: inkSm),
          ],
        ),
        if (guest)
          CssParagraph(l10n.settingsAssistantsGuest, style: mutedSm)
        else
          _Connected(
            timeZone: widget.timeZone,
            revoked: _revoked,
            onRevoke: (item) => unawaited(_revoke(item)),
          ),
      ],
    );
  }
}

/// "Asistentes conectados": the list, or that there are none, or that it could not be read.
class _Connected extends ConsumerWidget {
  const _Connected({required this.timeZone, required this.revoked, required this.onRevoke});

  final String timeZone;
  final Set<String> revoked;
  final void Function(ConnectedAssistant item) onRevoke;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final list = ref.watch(settingsAssistantListProvider);
    final items = list.value?.where((a) => !revoked.contains(a.clientId)).toList();
    final mutedSm = LkText.bodySm.copyWith(color: colors.inkMuted);
    String day(DateTime at) => passkeyDay(at, l10n.localeName, timeZone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: [
        SettingLabel(label: l10n.settingsAssistantsConnected),
        if (list.hasError && items == null)
          CssParagraph(l10n.settingsAssistantsListFailed, style: mutedSm),
        if (items != null && items.isEmpty)
          CssParagraph(
            l10n.settingsAssistantsEmpty,
            style: LkText.bodySm.copyWith(color: colors.ink),
          ),
        if (items != null)
          for (final item in items)
            _AssistantRow(
              key: Key('settings.assistants.row.${item.clientId}'),
              item: item,
              connected: day(item.connectedAt),
              lastUsed: switch (item.lastUsedAt) {
                final at? => day(at),
                null => null,
              },
              onRevoke: () => onRevoke(item),
            ),
      ],
    );
  }
}

/// One assistant: `lk-rowcard justify-between`, its name and where it comes from over when it was
/// connected and last used, and its "Revocar".
class _AssistantRow extends StatelessWidget {
  const _AssistantRow({
    super.key,
    required this.item,
    required this.connected,
    required this.lastUsed,
    required this.onRevoke,
  });

  final ConnectedAssistant item;
  final String connected;
  final String? lastUsed;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final muted = LkText.fieldLabel.copyWith(color: colors.inkMuted);
    final domain = item.domain;
    final lastUsed = this.lastUsed;
    return PressSurface(
      minSize: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: LkSurface.rowCard(lk),
      child: SizedBox(
        width: double.infinity,
        child: Row(
          spacing: 10,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CssBlinkLines(
                    style: LkText.body,
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LkText.body.copyWith(color: colors.ink),
                    ),
                  ),
                  if (domain != null)
                    CssBlinkLines(
                      style: LkText.fieldLabel,
                      child: Text(
                        domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                  Wrap(
                    spacing: WambitoTokens.space2,
                    children: [
                      CssBlinkLines(
                        style: LkText.fieldLabel,
                        child: Text(l10n.settingsAssistantsConnectedOn(connected), style: muted),
                      ),
                      CssBlinkLines(
                        style: LkText.fieldLabel,
                        child: Text(
                          lastUsed == null
                              ? l10n.settingsAssistantsNeverUsed
                              : l10n.settingsAssistantsLastUsed(lastUsed),
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PressButton(
              key: Key('settings.assistants.revoke.${item.clientId}'),
              tone: PressTone.ghost,
              size: PressSize.sm,
              semanticLabel: l10n.settingsAssistantsRevokeLabel(item.name),
              onPressed: onRevoke,
              child: OffsetUnderline(LkText.upperCase(l10n.settingsAssistantsRevoke)),
            ),
          ],
        ),
      ),
    );
  }
}
