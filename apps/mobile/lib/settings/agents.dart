// The four AI apps "Mis agentes" knows how to connect: the twin of the web's
// `apps/web/app/features/assistants/agents.ts` (same names, links, notices and matching rules).
import '../ui/lk_brand_logo.dart';
import 'assistants_repository.dart';

/// A notice the connect sheet shows before the steps.
enum AgentNote { plan, desktop, paid }

enum Agent {
  claude(
    label: 'Claude',
    brand: LkBrand.claude,
    connectorsUrl: 'https://claude.ai/settings/connectors',
    helpUrl: 'https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp',
    company: 'Claude',
  ),
  chatgpt(
    label: 'ChatGPT',
    brand: LkBrand.chatgpt,
    connectorsUrl: 'https://chatgpt.com/plugins',
    helpUrl:
        'https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt',
    company: 'OpenAI',
    note: AgentNote.plan,
  ),
  lumo(
    label: 'Lumo+',
    brand: LkBrand.lumo,
    connectorsUrl: 'https://proton.me/lumo/download',
    helpUrl: 'https://proton.me/support/lumo-connectors',
    company: 'Proton',
    note: AgentNote.desktop,
  ),
  grok(
    label: 'Grok',
    brand: LkBrand.grok,
    connectorsUrl: 'https://grok.com/connectors',
    helpUrl: 'https://docs.x.ai/grok/connectors',
    company: 'xAI',
    note: AgentNote.paid,
  );

  const Agent({
    required this.label,
    required this.brand,
    required this.connectorsUrl,
    required this.helpUrl,
    required this.company,
    this.note,
  });

  /// What the app is called on screen.
  final String label;
  final LkBrand brand;

  /// Where the app takes a custom connector (or where to get the app).
  final String connectorsUrl;

  /// The company's own step-by-step guide.
  final String helpUrl;

  /// Whose help centre the guide is in ("la ayuda de `company`").
  final String company;
  final AgentNote? note;

  /// Wambi's handshake scene with this app.
  String get scene => 'assets/wambi/handshake-$name.webp';
}

/// Wambito's names for each app, as whole words in a grant's name.
final _names = <Agent, RegExp>{
  for (final agent in Agent.values) agent: RegExp('\\b${agent.name}\\b', caseSensitive: false),
};

const _domains = <Agent, List<String>>{
  Agent.claude: ['claude.ai', 'anthropic.com'],
  Agent.chatgpt: ['chatgpt.com', 'openai.com'],
  Agent.lumo: ['lumo.proton.me'],
  Agent.grok: ['grok.com', 'x.ai'],
};

/// Which of the four apps an OAuth client is; null for any other. The name must hold the app's name
/// as a whole word; the domain must be the app's own or one of its subdomains, never a substring
/// ("box.ai" is not x.ai).
Agent? agentFor(ConnectedAssistant grant) {
  for (final entry in _names.entries) {
    if (entry.value.hasMatch(grant.name)) return entry.key;
  }
  final domain = (grant.domain ?? '').toLowerCase();
  if (domain.isEmpty) return null;
  for (final entry in _domains.entries) {
    for (final own in entry.value) {
      if (domain == own || domain.endsWith('.$own')) return entry.key;
    }
  }
  return null;
}
