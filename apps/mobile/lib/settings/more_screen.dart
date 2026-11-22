// Más (`/settings/more`), the light version (spec 2026-11-22; the web's `MoreScreen.tsx` has only
// "Comentarios e ideas"): a group with "Comentarios e ideas" (today's form in a sheet), "Lo que viene"
// and "Abrir Wambito en la web" (the same pages as before), and a second group with "Servidor" (its
// status as the value, the address as its line, today's change-server form) and "Acerca de" (the
// version), plus the debug-only PRF probe.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/server_url.dart';
import '../l10n/app_localizations.dart';
import '../progress/guest_warning.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart' show flexOneRow;
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import '../ui/web_text_field.dart';
import '../vault/unsynced_sheet.dart';
import '../vault/vault_providers.dart' show vaultSessionProvider;
import 'feedback.dart';
import 'leave_guard.dart';
import 'locale_resolution.dart';
import 'server_status.dart';
import 'settings_parts.dart';
import 'settings_screen.dart' show debugToolsProvider;
import 'url_opener.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key, this.webSectionsOnly = false});

  /// As `SettingsScreen.webSectionsOnly`: only what the web's page also has (feedback).
  final bool webSectionsOnly;

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  /// Changing server is under way (the old server is told, if it answers).
  bool _busy = false;

  Future<void> _changeServer() async {
    if (_busy) return;
    final next = await LkSheet.show<Uri>(
      context,
      title: AppLocalizations.of(context).settingsServerTitle,
      children: [_ServerForm(current: ref.read(serverUrlProvider))],
    );
    if (!mounted || next == null) return;
    if (next != ref.read(serverUrlProvider) &&
        !await mayLeaveSettings(context, ref, GuestLeaving.changeServer)) {
      return;
    }
    if (!mounted) return;
    // Another server signs out (and wipes the vault): a `preview` account's changes not sent yet
    // are asked about first, as at a sign-out.
    if (next != ref.read(serverUrlProvider) &&
        !await confirmUnsyncedSignOut(context, ref.read(vaultSessionProvider))) {
      return;
    }
    if (!mounted) return;
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final changed = await ref.read(serverUrlProvider.notifier).change(next.toString());
      if (changed) toasts.say(l10n.settingsServerChanged(next.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens one of the web's public pages in the browser: the landing, or the roadmap. They are
  /// prerendered per language, Spanish with no prefix and the others under `/en`, `/it` and `/pt`
  /// (the web's `LANDING_PATH` and `ROADMAP_PATH`).
  Future<void> _openWeb({bool roadmap = false}) async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    final server = ref.read(serverUrlProvider);
    final path = webPagePath(l10n.localeName, roadmap: roadmap);
    // The Spanish landing is the server's own address, as it always was.
    final page = path == '/' ? server : server.resolve(path);
    final opened = await ref.read(urlOpenerProvider).open(page);
    if (!opened && mounted) toasts.say(l10n.settingsWebFailed, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tint = context.lkColors.inkMuted;
    final server = ref.watch(serverUrlProvider);
    final version = ref.watch(appVersionProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        SettingsGroup(
          rows: [
            const FeedbackSection(),
            if (!widget.webSectionsOnly) ...[
              SettingsRow(
                key: const Key('settings.roadmap'),
                icon: LkIcon(LkIconName.map, size: 20, color: tint),
                title: l10n.settingsRoadmapRow,
                trailing: const RowChevron(),
                onTap: () => unawaited(_openWeb(roadmap: true)),
              ),
              SettingsRow(
                key: const Key('settings.web'),
                icon: LkIcon(LkIconName.globe, size: 20, color: tint),
                title: l10n.settingsWebRow,
                line: l10n.settingsWebHint,
                trailing: const RowChevron(),
                onTap: () => unawaited(_openWeb()),
              ),
            ],
          ],
        ),
        if (!widget.webSectionsOnly)
          SettingsGroup(
            rows: [
              SettingsRow(
                key: const Key('settings.server'),
                icon: LkIcon(LkIconName.server, size: 20, color: tint),
                title: l10n.settingsServer,
                line: server.toString(),
                trailing: const RowCustom(ServerStatus(compact: true)),
                onTap: _busy ? null : () => unawaited(_changeServer()),
              ),
              SettingsRow(
                key: const Key('settings.about'),
                icon: LkIcon(LkIconName.info, size: 20, color: tint),
                title: l10n.settingsAbout,
                line: version == null ? null : l10n.settingsAboutVersion(version),
                semanticsHint: l10n.aboutLegalese,
                trailing: const RowChevron(),
                onTap: () => unawaited(context.push<void>('/settings/about')),
              ),
              if (ref.watch(debugToolsProvider))
                SettingsRow(
                  key: const Key('settings.prfProbe'),
                  icon: LkIcon(LkIconName.key, size: 20, color: tint),
                  title: 'PRF probe',
                  trailing: const RowChevron(),
                  onTap: () => unawaited(context.push<void>('/debug/prf')),
                ),
            ],
          ),
      ],
    );
  }
}

/// The server address, asked for in a sheet: [current] to start with. Pops the checked address, or
/// null. The sheet is `Sheet` as the web's delete-account one is: what it is about, the field with
/// its label, what is wrong with it, and the ways out.
class _ServerForm extends StatefulWidget {
  const _ServerForm({required this.current});

  final Uri current;

  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  late final _field = TextEditingController(text: widget.current.toString());
  final _focus = FocusNode();
  bool _invalid = false;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final url = parseServerUrl(_field.text);
    if (url == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final wide = MediaQuery.sizeOf(context).width >= 400;
    final change = PressButton.text(
      l10n.settingsServerChange,
      key: const Key('settings.server.change'),
      onPressed: _submit,
    );
    final cancel = PressButton.text(
      l10n.cancel,
      tone: PressTone.ghost,
      onPressed: () => Navigator.of(context).pop(),
    );
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space4,
        children: [
          Text(l10n.settingsServerLead, style: LkText.body.copyWith(color: colors.ink)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space1,
            children: [
              Text(l10n.settingsServerField, style: LkText.bodySm.copyWith(color: colors.ink)),
              WebTextField(
                controller: _field,
                focusNode: _focus,
                fieldKey: const Key('settings.server.field'),
                label: l10n.settingsServerField,
                invalid: _invalid,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_invalid) setState(() => _invalid = false);
                },
              ),
            ],
          ),
          if (_invalid)
            Semantics(
              liveRegion: true,
              container: true,
              child: Text(
                l10n.settingsServerInvalid,
                style: LkText.body.copyWith(color: colors.over),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: PressButton.text(
              l10n.settingsServerUseDefault,
              key: const Key('settings.server.default'),
              tone: PressTone.ghost,
              onPressed: () => setState(() {
                _field.text = defaultServerUrl.toString();
                _invalid = false;
              }),
            ),
          ),
          if (wide)
            // The ghost has 8px of padding each side, the primary 24px.
            flexOneRow(gap: WambitoTokens.space2, items: [(16, cancel), (48, change)])
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WambitoTokens.space2,
              children: [change, cancel],
            ),
        ],
      ),
    );
  }
}
