// "Mis agentes" in Settings (spec 2026-11-22, the twin of the web's AgentsScreen): the four AI apps
// (Claude, ChatGPT, Lumo+, Grok) with their state, each with "Conectar" (a sheet with Wambi's
// handshake and the steps) or, once connected, when it was connected and last used with "Revocar"
// (which ends every grant of the app); any other client that was let in after them; and the
// connector's address. Back in the app the list is read again, and a new grant of one of the four
// says so once. Connecting happens in the app and on the web's consent screen; the phone only
// reads and revokes. A guest is told to add an email first. An encrypted (`preview`) account sees
// the same: the server's MCP opens its data once the person opens it on the consent page.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/server_url.dart';
import '../api/session.dart';
import '../capture/parser/dates.dart' show todayIn;
import '../home/home_controller.dart' show clockProvider;
import '../home/home_repository.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/css_text.dart';
import '../ui/lk_brand_logo.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart' show PressTone;
import '../ui/toast.dart';
import '../vault/vault_providers.dart' show vaultGateProvider;
import 'agents.dart';
import 'assistants_repository.dart';
import 'connect_agent_sheet.dart';
import 'passkeys_section.dart' show passkeyDay;
import 'profile_settings.dart' show profileFailureMessage;
import 'settings_parts.dart';
import 'url_opener.dart';

/// The connected assistants, read when Settings opens and again on coming back to the app.
final settingsAssistantListProvider = FutureProvider.autoDispose<List<ConnectedAssistant>>(
  (ref) => ref.watch(assistantsRepositoryProvider).list(),
  // The page says it could not load them; opening Settings again asks again.
  retry: (_, _) => null,
);

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key, required this.timeZone, required this.guest});

  /// The profile's zone: the dates are in it.
  final String timeZone;

  /// A guest is told to add an email first instead of seeing the list.
  final bool guest;

  @override
  ConsumerState<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends ConsumerState<AgentsScreen> with WidgetsBindingObserver {
  /// Revoked here: gone from the list until it is read again.
  final _revoked = <String>{};

  /// The grant ids already seen: null until the first load, so that one never says anything.
  Set<String>? _seen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from connecting in the other app.
    if (state == AppLifecycleState.resumed && !widget.guest) {
      ref.invalidate(settingsAssistantListProvider);
    }
  }

  /// Reads the list again; what was revoked here is then really gone from it.
  Future<void> _refresh() async {
    ref.invalidate(settingsAssistantListProvider);
    try {
      await ref.read(settingsAssistantListProvider.future);
    } on Object {
      // The page says it could not load them.
    }
    if (mounted && _revoked.isNotEmpty) setState(_revoked.clear);
  }

  void _onList(AsyncValue<List<ConnectedAssistant>> next) {
    if (next case AsyncData(:final value)) {
      final before = _seen;
      _seen = {for (final item in value) item.clientId};
      if (before == null) return;
      final l10n = AppLocalizations.of(context);
      final toasts = ToastHost.of(context);
      for (final item in value) {
        if (before.contains(item.clientId)) continue;
        final agent = agentFor(item);
        if (agent != null) toasts.say(l10n.settingsAgentsNowConnected(agent.label));
      }
    }
  }

  Future<void> _copy(Uri url) async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    await Clipboard.setData(ClipboardData(text: url.toString()));
    toasts.say(l10n.settingsAssistantsCopied);
  }

  Future<void> _revoke(String name, List<ConnectedAssistant> grants) async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    final revoked = await ConfirmSheet.show(
      context,
      title: l10n.settingsAssistantsRevokeTitle(name),
      body: l10n.settingsAssistantsRevokeBody,
      confirmLabel: l10n.settingsAssistantsRevokeConfirm,
      confirmKey: const Key('settings.assistants.revoke.confirm'),
      onConfirm: () async {
        try {
          // Every grant of the app: one that is left would keep it connected.
          for (final grant in grants) {
            await ref.read(assistantsRepositoryProvider).revoke(grant.clientId);
          }
        } on Object catch (error) {
          final failure = error is HomeFailure ? error : const HomeFailure(0);
          // The server no longer knows the session: signed out, as every other call ends it.
          if (failure.unauthorized) {
            unawaited(ref.read(sessionProvider.notifier).signOut(discardGuest: true));
          }
          // The session now belongs to another account: nothing was revoked, and the vault's gate
          // checks who is signed in (reloads for them), as for its sync's 409.
          if (failure.status == 409 && failure.code == 'session_changed') {
            ref.read(vaultGateProvider)?.sessionChanged();
          }
          // The sheet stays for another try, and says why; the list shows what did go.
          toasts.say(profileFailureMessage(l10n, failure), error: true);
          unawaited(_refresh());
          rethrow;
        }
        toasts.say(l10n.settingsAssistantsRevoked(name));
      },
    );
    if (revoked && mounted) {
      setState(() => _revoked.addAll(grants.map((grant) => grant.clientId)));
      unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.guest) {
      return SettingsSection(
        key: const Key('settings.card.assistants'),
        title: l10n.settingsAgentsGuestTitle,
        children: [
          CssParagraph(
            l10n.settingsAssistantsGuest,
            style: LkText.bodySm.copyWith(color: context.lkColors.ink),
          ),
        ],
      );
    }
    ref.listen(settingsAssistantListProvider, (_, next) => _onList(next));
    final colors = context.lkColors;
    final list = ref.watch(settingsAssistantListProvider);
    final grants = list.value?.where((item) => !_revoked.contains(item.clientId)).toList();
    final url = mcpUrl(ref.watch(serverUrlProvider));
    final mutedSm = LkText.bodySm.copyWith(color: colors.inkMuted);
    final opener = ref.read(urlOpenerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space4,
      children: [
        CssParagraph(l10n.settingsAgentsLead, style: mutedSm),
        if (list.hasError && grants == null)
          CssParagraph(l10n.settingsAssistantsListFailed, style: mutedSm),
        if (grants != null)
          SettingsGroup(
            rows: [
              for (final agent in Agent.values)
                _agentRow(
                  context,
                  agent,
                  grants.where((item) => agentFor(item) == agent).toList(),
                  url,
                  opener,
                ),
              for (final grant in grants.where((item) => agentFor(item) == null))
                _otherRow(context, grant),
            ],
          ),
        SettingsSection(
          key: const Key('settings.card.assistants'),
          title: l10n.settingsAgentsAddressTitle,
          children: [
            AddressField(
              url: url,
              onCopy: () => unawaited(_copy(url)),
              urlKey: const Key('settings.assistants.url'),
              copyKey: const Key('settings.assistants.copy'),
            ),
          ],
        ),
      ],
    );
  }

  /// What a row's muted line says of a grant: when it was connected and last used.
  String _line(AppLocalizations l10n, ConnectedAssistant grant) {
    String day(DateTime at) => passkeyDay(at, l10n.localeName, widget.timeZone);
    final at = grant.lastUsedAt;
    final String used;
    if (at == null) {
      used = l10n.settingsAgentsNeverUsed;
    } else {
      final now = ref.read(clockProvider)().toUtc();
      final key = todayIn(widget.timeZone, at.toUtc());
      if (key == todayIn(widget.timeZone, now)) {
        used = l10n.settingsAgentsUsedToday;
      } else if (key == todayIn(widget.timeZone, now.subtract(const Duration(days: 1)))) {
        used = l10n.settingsAgentsUsedYesterday;
      } else {
        used = l10n.settingsAgentsUsedOn(day(at));
      }
    }
    return l10n.settingsAgentsConnectedLine(day(grant.connectedAt), used);
  }

  Widget _tile(BuildContext context, Widget icon) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.lkColors.surfaceSunken,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(child: icon),
  );

  Widget _agentRow(
    BuildContext context,
    Agent agent,
    List<ConnectedAssistant> own,
    Uri url,
    UrlOpener opener,
  ) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final newest = own.isEmpty
        ? null
        : own.reduce((a, b) => b.connectedAt.isAfter(a.connectedAt) ? b : a);
    return SettingsRow(
      key: Key('settings.agents.row.${agent.name}'),
      icon: _tile(context, LkBrandLogo(agent.brand, size: 18, color: colors.ink)),
      title: agent.label,
      line: newest == null ? l10n.settingsAgentsNotConnected : _line(l10n, newest),
      trailing: newest == null
          ? RowButton(
              label: l10n.settingsAgentsConnect,
              semanticLabel: l10n.settingsAgentsConnectLabel(agent.label),
              buttonKey: Key('settings.agents.connect.${agent.name}'),
              onPressed: () => unawaited(
                showConnectAgentSheet(
                  context,
                  agent: agent,
                  url: url,
                  onCopy: () => unawaited(_copy(url)),
                  opener: opener,
                ),
              ),
            )
          : RowButton(
              label: l10n.settingsAssistantsRevoke,
              semanticLabel: l10n.settingsAssistantsRevokeLabel(agent.label),
              tone: PressTone.ghost,
              buttonKey: Key('settings.agents.revoke.${agent.name}'),
              onPressed: () => unawaited(_revoke(agent.label, own)),
            ),
    );
  }

  Widget _otherRow(BuildContext context, ConnectedAssistant grant) {
    final l10n = AppLocalizations.of(context);
    return SettingsRow(
      key: Key('settings.agents.row.${grant.clientId}'),
      icon: _tile(context, LkIcon(LkIconName.chat, size: 18, color: context.lkColors.ink)),
      title: grant.name,
      line: _line(l10n, grant),
      trailing: RowButton(
        label: l10n.settingsAssistantsRevoke,
        semanticLabel: l10n.settingsAssistantsRevokeLabel(grant.name),
        tone: PressTone.ghost,
        buttonKey: Key('settings.agents.revoke.${grant.clientId}'),
        onPressed: () => unawaited(_revoke(grant.name, [grant])),
      ),
    );
  }
}
