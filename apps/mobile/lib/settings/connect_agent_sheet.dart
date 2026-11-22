// "Conectar <app>" (the web's ConnectAgentSheet, apps/web/app/features/assistants/): Wambi shaking
// hands with the app, a notice if the app has one, three steps (copy the address, paste it in the
// app, sign in with the Wambito account), the guide's link and two things to ask. Closes with
// "Listo". The app's logo appears only in the scene.
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/offset_underline.dart';
import '../ui/press_button.dart';
import '../ui/pressable.dart';
import '../ui/sheet.dart';
import '../theme/surfaces.dart';
import 'agents.dart';
import 'url_opener.dart';

/// The connector's address, read-only, with "Copiar". [urlKey] and [copyKey] find them (tests).
class AddressField extends StatelessWidget {
  const AddressField({
    super.key,
    required this.url,
    required this.onCopy,
    this.urlKey,
    this.copyKey,
  });

  final Uri url;
  final VoidCallback onCopy;
  final Key? urlKey;
  final Key? copyKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    return PressSurface(
      minSize: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: LkSurface.rowCard(lk),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            // Plain text: the button copies it.
            child: Text(
              url.toString(),
              key: urlKey,
              style: LkText.body.copyWith(color: lk.colors.ink),
            ),
          ),
          PressButton(
            key: copyKey,
            tone: PressTone.ghost,
            size: PressSize.sm,
            semanticLabel: l10n.settingsAssistantsCopyLabel,
            onPressed: onCopy,
            child: OffsetUnderline(LkText.upperCase(l10n.settingsAssistantsCopy)),
          ),
        ],
      ),
    );
  }
}

/// Opens the sheet for [agent]. [onCopy] copies the address (and says so); the app's page and
/// guide open through [opener].
Future<void> showConnectAgentSheet(
  BuildContext context, {
  required Agent agent,
  required Uri url,
  required VoidCallback onCopy,
  required UrlOpener opener,
}) {
  final l10n = AppLocalizations.of(context);
  return LkSheet.show<void>(
    context,
    title: l10n.settingsAgentsConnectTitle(agent.label),
    children: [_ConnectBody(agent: agent, url: url, onCopy: onCopy, opener: opener)],
  );
}

String _step2(AppLocalizations l10n, Agent agent) => switch (agent) {
  Agent.claude => l10n.settingsAgentsStep2Claude,
  Agent.chatgpt => l10n.settingsAgentsStep2Chatgpt,
  Agent.lumo => l10n.settingsAgentsStep2Lumo,
  Agent.grok => l10n.settingsAgentsStep2Grok,
};

String _open(AppLocalizations l10n, Agent agent) => switch (agent) {
  Agent.claude => l10n.settingsAgentsOpenClaude,
  Agent.chatgpt => l10n.settingsAgentsOpenChatgpt,
  Agent.lumo => l10n.settingsAgentsOpenLumo,
  Agent.grok => l10n.settingsAgentsOpenGrok,
};

String _note(AppLocalizations l10n, AgentNote note) => switch (note) {
  AgentNote.plan => l10n.settingsAgentsNotePlan,
  AgentNote.desktop => l10n.settingsAgentsNoteDesktop,
  AgentNote.paid => l10n.settingsAgentsNotePaid,
};

/// [text] with its `<b>…</b>` parts in bold.
List<InlineSpan> boldSpans(String text, TextStyle base) {
  final bold = base.copyWith(fontWeight: FontWeight.w900);
  final spans = <InlineSpan>[];
  var at = 0;
  for (final match in RegExp('<b>(.*?)</b>').allMatches(text)) {
    if (match.start > at) spans.add(TextSpan(text: text.substring(at, match.start)));
    spans.add(TextSpan(text: match.group(1), style: bold));
    at = match.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

class _ConnectBody extends StatelessWidget {
  const _ConnectBody({
    required this.agent,
    required this.url,
    required this.onCopy,
    required this.opener,
  });

  final Agent agent;
  final Uri url;
  final VoidCallback onCopy;
  final UrlOpener opener;

  void _launch(String address) => unawaited(opener.open(Uri.parse(address)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final body = LkText.body.copyWith(color: colors.ink);
    final note = agent.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space4,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: ExcludeSemantics(child: Image.asset(agent.scene, fit: BoxFit.contain)),
          ),
        ),
        if (note != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(_note(l10n, note), style: LkText.bodySm.copyWith(color: colors.ink)),
            ),
          ),
        _Step(
          n: 1,
          children: [
            Text(l10n.settingsAgentsStep1, style: body),
            AddressField(
              url: url,
              onCopy: onCopy,
              copyKey: const Key('settings.agents.sheet.copy'),
            ),
          ],
        ),
        _Step(
          n: 2,
          children: [
            Text.rich(TextSpan(children: boldSpans(_step2(l10n, agent), body)), style: body),
            PressButton(
              key: const Key('settings.agents.sheet.open'),
              tone: PressTone.ghost,
              size: PressSize.sm,
              semanticLabel: _open(l10n, agent),
              onPressed: () => _launch(agent.connectorsUrl),
              child: OffsetUnderline(LkText.upperCase(_open(l10n, agent))),
            ),
          ],
        ),
        _Step(n: 3, children: [Text(l10n.settingsAgentsStep3(agent.label), style: body)]),
        _Help(agent: agent, opener: opener),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space2,
          children: [
            Text(
              l10n.settingsAssistantsExamples,
              style: body.copyWith(fontWeight: FontWeight.w900),
            ),
            Wrap(
              spacing: WambitoTokens.space2,
              runSpacing: WambitoTokens.space2,
              children: [
                for (final example in [
                  l10n.settingsAssistantsExampleAdd,
                  l10n.settingsAssistantsExampleAsk,
                ])
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceRow,
                      border: Border.all(color: colors.stroke, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Text(example, style: LkText.bodySm.copyWith(color: colors.ink)),
                    ),
                  ),
              ],
            ),
          ],
        ),
        PressButton(
          key: const Key('settings.agents.sheet.done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LkText.upperCase(l10n.settingsAgentsDone)),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.children});

  final int n;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colors.surfaceSunken, shape: BoxShape.circle),
            child: Text('$n', style: LkText.label.copyWith(color: colors.ink)),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space2,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// "¿Te perdiste? Mira la guía paso a paso en la ayuda de `company` ↗": the link opens the
/// company's guide.
class _Help extends StatelessWidget {
  const _Help({required this.agent, required this.opener});

  final Agent agent;
  final UrlOpener opener;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final style = LkText.fieldLabel.copyWith(color: colors.inkMuted, fontWeight: FontWeight.w700);
    final text = l10n.settingsAgentsHelp(agent.company);
    final match = RegExp('^(.*?)<link>(.*?)</link>(.*)\$', dotAll: true).firstMatch(text);
    if (match == null) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: match.group(1)),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Pressable(
              key: const Key('settings.agents.sheet.help'),
              link: true,
              onPressed: () => unawaited(opener.open(Uri.parse(agent.helpUrl))),
              builder: (context, state) => Text(
                match.group(2)!,
                style: style.copyWith(
                  color: colors.ink,
                  decoration: TextDecoration.underline,
                  decorationThickness: 2,
                ),
              ),
            ),
          ),
          TextSpan(text: match.group(3)),
        ],
      ),
      style: style,
    );
  }
}
