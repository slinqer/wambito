// "Mis agentes" in Settings (spec 2026-11-22), the phone's twin of the web's AgentsScreen stories:
// the four AI apps with their state, "Conectar" (a sheet with Wambi's handshake and the steps) or,
// once connected, when and "Revocar" (every grant of the app at once); any other client after them;
// the connector's address below. A guest is told to add an email first. An encrypted (`preview`)
// account sees the same.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/server_url.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/router.dart';
import 'package:wambito/settings/agents.dart';
import 'package:wambito/settings/assistants_repository.dart';
import 'package:wambito/settings/initial_settings.dart';
import 'package:wambito/ui/lk_brand_logo.dart';
import 'package:wambito/ui/lk_icons.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../home/fakes.dart';
import '../support/preview_account.dart';
import 'fakes.dart';
import 'harness.dart';

final _now = DateTime.utc(2026, 10, 31, 15);

const _claudeId = 'https://claude.ai/oauth/mcp-oauth-client-metadata';

ConnectedAssistant _claude({String id = _claudeId, DateTime? connectedAt}) => ConnectedAssistant(
  clientId: id,
  name: 'Claude',
  domain: 'claude.ai',
  connectedAt: connectedAt ?? DateTime.utc(2026, 10, 2, 14),
  lastUsedAt: DateTime.utc(2026, 10, 20, 9),
);

ConnectedAssistant _chatGpt() => ConnectedAssistant(
  clientId: 'chatgpt-1',
  name: 'ChatGPT',
  domain: 'chatgpt.com',
  // 02:00 UTC is still the day before in Bogota.
  connectedAt: DateTime.utc(2026, 10, 5, 2),
);

ConnectedAssistant _cursor() => ConnectedAssistant(
  clientId: 'cursor-1',
  name: 'Cursor',
  domain: 'cursor.com',
  connectedAt: DateTime.utc(2026, 10, 9, 15),
  // 20:00 UTC on the 30th is 15:00 in Bogota: yesterday.
  lastUsedAt: DateTime.utc(2026, 10, 30, 20),
);

Future<SettingsEnv> _pump(
  WidgetTester t, {
  required FakeAssistantsRepository assistants,
  bool guest = false,
  Locale locale = const Locale('es'),
  List<Override> overrides = const [],
}) async {
  final env = await pumpSettingsApp(
    t,
    guest: guest,
    locale: locale,
    homeRepo: FakeHomeRepository(timezone: 'America/Bogota'),
    overrides: [
      clockProvider.overrideWithValue(() => _now),
      assistantsRepositoryProvider.overrideWithValue(assistants),
      ...overrides,
    ],
  );
  env.container.read(routerProvider).go('/settings/agents');
  await t.pumpAndSettle();
  return env;
}

/// A test with the screen reader's tree on, for the texts [said] finds.
void testPage(String name, Future<void> Function(WidgetTester t) body) =>
    testWidgets(name, (t) async {
      final handle = t.ensureSemantics();
      await body(t);
      handle.dispose();
    });

Finder said(String text) => find.bySemanticsLabel(text);

Future<void> _scrollTo(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

Finder _row(String id) => find.byKey(Key('settings.agents.row.$id'));
Finder _connect(String id) => find.byKey(Key('settings.agents.connect.$id'));
Finder _revoke(String id) => find.byKey(Key('settings.agents.revoke.$id'));
const _confirm = Key('settings.assistants.revoke.confirm');

void main() {
  group('agentFor', () {
    ConnectedAssistant grant(String name, [String? domain]) => ConnectedAssistant(
      clientId: 'id',
      name: name,
      domain: domain,
      connectedAt: DateTime.utc(2026),
    );

    test('knows the four apps by name or domain, in any case', () {
      expect(agentFor(grant('Claude')), Agent.claude);
      expect(agentFor(grant('mcp client', 'anthropic.com')), Agent.claude);
      expect(agentFor(grant('ChatGPT', 'chatgpt.com')), Agent.chatgpt);
      expect(agentFor(grant('x', 'OpenAI.com')), Agent.chatgpt);
      expect(agentFor(grant('Lumo')), Agent.lumo);
      expect(agentFor(grant('Proton Lumo+')), Agent.lumo);
      expect(agentFor(grant('Grok')), Agent.grok);
      expect(agentFor(grant('x', 'api.x.ai')), Agent.grok);
      expect(agentFor(grant('Lumo', 'lumo.proton.me')), Agent.lumo);
      expect(agentFor(grant('mcp', 'claude.ai')), Agent.claude);
    });

    test('is null for any other client', () {
      expect(agentFor(grant('Cursor')), isNull);
      expect(agentFor(grant('Cursor', 'cursor.com')), isNull);
      expect(agentFor(grant('Cursor', null)), isNull);
      expect(agentFor(grant('Box AI', 'box.ai')), isNull);
      expect(agentFor(grant('Proton Mail bridge', 'proton.me')), isNull);
      expect(agentFor(grant('OpenAI Codex')), isNull);
    });
  });

  group('Agent', () {
    test('lists Claude, ChatGPT, Lumo+ and Grok in that order with their links', () {
      expect(Agent.values.map((a) => (a.name, a.label, a.brand)), [
        ('claude', 'Claude', LkBrand.claude),
        ('chatgpt', 'ChatGPT', LkBrand.chatgpt),
        ('lumo', 'Lumo+', LkBrand.lumo),
        ('grok', 'Grok', LkBrand.grok),
      ]);
      for (final agent in Agent.values) {
        expect(agent.scene, 'assets/wambi/handshake-${agent.name}.webp');
      }
      expect(Agent.values.map((a) => a.connectorsUrl), [
        'https://claude.ai/settings/connectors',
        'https://chatgpt.com/plugins',
        'https://proton.me/lumo/download',
        'https://grok.com/connectors',
      ]);
      expect(Agent.values.map((a) => a.helpUrl), [
        'https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp',
        'https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt',
        'https://proton.me/support/lumo-connectors',
        'https://docs.x.ai/grok/connectors',
      ]);
      expect(Agent.values.map((a) => a.note), [
        null,
        AgentNote.plan,
        AgentNote.desktop,
        AgentNote.paid,
      ]);
      expect(Agent.values.map((a) => a.company), ['Claude', 'OpenAI', 'Proton', 'xAI']);
    });
  });

  group('the list', () {
    testPage('shows the four apps in order, then any other client, with their state', (t) async {
      await _pump(t, assistants: FakeAssistantsRepository([_cursor(), _chatGpt(), _claude()]));
      expect(said('Mis agentes'), findsWidgets);
      final ys = [
        for (final id in ['claude', 'chatgpt', 'lumo', 'grok', 'cursor-1'])
          t.getTopLeft(_row(id)).dy,
      ];
      expect([...ys]..sort(), ys, reason: 'Claude, ChatGPT, Lumo+, Grok, then Cursor');

      expect(
        find.descendant(
          of: _row('claude'),
          matching: find.text('Conectado el 2 oct 2026 · usado el 20 oct 2026'),
        ),
        findsOneWidget,
      );
      expect(_revoke('claude'), findsOneWidget);
      expect(_connect('claude'), findsNothing);
      expect(
        find.descendant(
          of: _row('chatgpt'),
          matching: find.text('Conectado el 4 oct 2026 · aún sin usar'),
        ),
        findsOneWidget,
        reason: 'in Bogota\'s day',
      );
      expect(_revoke('chatgpt'), findsOneWidget);
      expect(
        find.descendant(of: _row('lumo'), matching: find.text('Sin conectar')),
        findsOneWidget,
      );
      expect(said('Conectar Lumo+'), findsOneWidget);
      expect(
        find.descendant(of: _row('grok'), matching: find.text('Sin conectar')),
        findsOneWidget,
      );
      expect(said('Conectar Grok'), findsOneWidget);
      expect(find.descendant(of: _row('cursor-1'), matching: find.text('Cursor')), findsOneWidget);
      expect(
        find.descendant(
          of: _row('cursor-1'),
          matching: find.text('Conectado el 9 oct 2026 · usado ayer'),
        ),
        findsOneWidget,
      );
      expect(said('Revocar Cursor'), findsOneWidget);

      // Each app has its own logo; any other client has the generic chat icon.
      for (final id in ['claude', 'chatgpt', 'lumo', 'grok']) {
        expect(
          find.descendant(of: _row(id), matching: find.byType(LkBrandLogo)),
          findsOneWidget,
          reason: id,
        );
      }
      expect(
        find.descendant(of: _row('cursor-1'), matching: find.byType(LkBrandLogo)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _row('cursor-1'),
          matching: find.byWidgetPredicate((w) => w is LkIcon && w.name == LkIconName.chat),
        ),
        findsOneWidget,
      );
    });

    testPage('with none connected, every app says Sin conectar and offers Conectar', (t) async {
      await _pump(t, assistants: FakeAssistantsRepository());
      expect(find.text('Sin conectar'), findsNWidgets(4));
      for (final id in ['claude', 'chatgpt', 'lumo', 'grok']) {
        expect(_connect(id), findsOneWidget);
      }
      expect(said('Revocar Claude'), findsNothing);
    });

    testPage('one row per app, with the newest grant\'s dates', (t) async {
      await _pump(
        t,
        assistants: FakeAssistantsRepository([
          _claude(id: 'claude-new', connectedAt: DateTime.utc(2026, 10, 25, 14)),
          _claude(),
        ]),
      );
      expect(_row('claude'), findsOneWidget);
      expect(
        find.descendant(
          of: _row('claude'),
          matching: find.text('Conectado el 25 oct 2026 · usado el 20 oct 2026'),
        ),
        findsOneWidget,
      );
    });

    testPage('in Italian at 130 % on 360 px a connected row stays one line, 76 px at most', (
      t,
    ) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(t, locale: const Locale('it'), assistants: FakeAssistantsRepository([_claude()]));
      t.view.physicalSize = const Size(360, 800);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(
        find.descendant(
          of: _row('claude'),
          matching: find.text('Collegato il 2 ott 2026 · usato il 20 ott 2026'),
        ),
        findsOneWidget,
      );
      expect(t.getSize(_row('claude')).height, lessThanOrEqualTo(76));
    });

    testPage('says when the list cannot be read', (t) async {
      final assistants = FakeAssistantsRepository()..listFailure = const HomeFailure(0);
      await _pump(t, assistants: assistants);
      expect(
        said('No pudimos cargar tus asistentes. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
    });

    testPage('in English', (t) async {
      await _pump(t, locale: const Locale('en'), assistants: FakeAssistantsRepository([_claude()]));
      expect(said('My agents'), findsWidgets);
      expect(find.text('Connected on Oct 2, 2026 · used on Oct 20, 2026'), findsOneWidget);
      expect(said('Revoke Claude'), findsOneWidget);
      expect(said('Connect Grok'), findsOneWidget);
    });
  });

  group('the connector address', () {
    late String? clipboard;
    setUp(() {
      clipboard = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    testPage('is below the list, follows the server and copies', (t) async {
      final env = await _pump(
        t,
        assistants: FakeAssistantsRepository(),
        overrides: [
          initialSettingsProvider.overrideWithValue(
            InitialSettings(
              serverUrl: Uri.parse('https://wambito.example.test'),
              themeMode: ThemeMode.dark,
            ),
          ),
        ],
      );
      await _scrollTo(t, find.byKey(const Key('settings.assistants.copy')));
      expect(said('La dirección de Wambito'), findsWidgets);
      expect(find.text('https://wambito.example.test/mcp'), findsOneWidget);
      expect(
        t.getTopLeft(find.byKey(const Key('settings.assistants.url'))).dy,
        greaterThan(t.getBottomLeft(_row('grok')).dy),
      );
      await t.tap(find.byKey(const Key('settings.assistants.copy')));
      await t.pumpAndSettle();
      expect(clipboard, mcpUrl(env.container.read(serverUrlProvider)).toString());
      expect(find.text('Copiamos la dirección.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('the connect sheet', () {
    testPage('Claude: the scene, three steps, the guide and things to ask', (t) async {
      final env = await _pump(t, assistants: FakeAssistantsRepository());
      await t.tap(_connect('claude'));
      await t.pumpAndSettle();
      expect(said('Conectar Claude'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == 'assets/wambi/handshake-claude.webp',
        ),
        findsOneWidget,
      );
      expect(find.text('Copia la dirección del conector'), findsOneWidget);
      expect(
        find.textContaining('Añadir conector personalizado', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Claude te pedirá entrar: usa tu cuenta de Wambito y acepta el permiso.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Solo desde la app de escritorio'), findsNothing);
      expect(find.textContaining('Se agrega desde la web de ChatGPT'), findsNothing);
      expect(find.text('«anota 18 lukas en almuerzo»'), findsOneWidget);

      await t.tap(find.byKey(const Key('settings.agents.sheet.open')));
      await t.pumpAndSettle();
      expect(env.opener.opened, [Uri.parse('https://claude.ai/settings/connectors')]);

      await t.tap(find.byKey(const Key('settings.agents.sheet.help')));
      await t.pumpAndSettle();
      expect(env.opener.opened.last, Uri.parse(Agent.claude.helpUrl));

      await t.tap(find.byKey(const Key('settings.agents.sheet.done')));
      await t.pumpAndSettle();
      expect(find.text('Copia la dirección del conector'), findsNothing);
    });

    testPage('the sheet copies the address too', (t) async {
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final env = await _pump(t, assistants: FakeAssistantsRepository());
      await t.tap(_connect('claude'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings.agents.sheet.copy')));
      await t.pumpAndSettle();
      expect(clipboard, mcpUrl(env.container.read(serverUrlProvider)).toString());
      await t.pump(const Duration(seconds: 10));
    });

    testPage('ChatGPT, Lumo+ and Grok each say what is special about them', (t) async {
      final env = await _pump(t, assistants: FakeAssistantsRepository());
      await t.tap(_connect('chatgpt'));
      await t.pumpAndSettle();
      expect(said('Conectar ChatGPT'), findsWidgets);
      expect(find.textContaining('Se agrega desde la web de ChatGPT'), findsOneWidget);
      expect(find.textContaining('Create as a plugin', findRichText: true), findsOneWidget);
      expect(find.textContaining('ayuda de OpenAI', findRichText: true), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.agents.sheet.open')));
      await t.pumpAndSettle();
      expect(env.opener.opened.last, Uri.parse('https://chatgpt.com/plugins'));
      await t.tap(find.byKey(const Key('settings.agents.sheet.done')));
      await t.pumpAndSettle();

      await t.tap(_connect('lumo'));
      await t.pumpAndSettle();
      expect(find.textContaining('Solo desde la app de escritorio de Lumo'), findsOneWidget);
      expect(said('Descargar Lumo ↗'), findsOneWidget);
      expect(find.textContaining('ayuda de Proton', findRichText: true), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.agents.sheet.done')));
      await t.pumpAndSettle();

      await t.tap(_connect('grok'));
      await t.pumpAndSettle();
      expect(find.textContaining('planes de pago de Grok'), findsOneWidget);
      expect(said('Abrir Grok ↗'), findsOneWidget);
      expect(find.textContaining('ayuda de xAI', findRichText: true), findsOneWidget);
    });
  });

  group('Revocar', () {
    testPage('asks first, then revokes and the app goes back to Conectar', (t) async {
      final assistants = FakeAssistantsRepository([_claude(), _chatGpt()]);
      await _pump(t, assistants: assistants);
      await t.tap(_revoke('claude'));
      await t.pumpAndSettle();
      expect(find.text('¿Revocar Claude?'), findsOneWidget);
      expect(assistants.revokes, isEmpty, reason: 'nothing before the answer');
      await t.tap(find.byKey(_confirm));
      await t.pumpAndSettle();
      expect(assistants.revokes, [_claudeId]);
      expect(find.text('Revocamos Claude.'), findsOneWidget);
      expect(_revoke('claude'), findsNothing);
      expect(_connect('claude'), findsOneWidget);
      expect(_revoke('chatgpt'), findsOneWidget, reason: 'the other one stays');
      await t.pump(const Duration(seconds: 10));
    });

    testPage('two grants of Claude are revoked together, and the list is read once more', (
      t,
    ) async {
      final assistants = FakeAssistantsRepository([
        _claude(id: 'claude-new', connectedAt: DateTime.utc(2026, 10, 25, 14)),
        _claude(),
      ]);
      await _pump(t, assistants: assistants);
      final before = assistants.lists;
      await t.tap(_revoke('claude'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(_confirm));
      await t.pumpAndSettle();
      expect(assistants.revokes, unorderedEquals(['claude-new', _claudeId]));
      expect(assistants.lists, before + 1);
      expect(_connect('claude'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('another client is revoked by itself', (t) async {
      final assistants = FakeAssistantsRepository([_claude(), _cursor()]);
      await _pump(t, assistants: assistants);
      await t.tap(_revoke('cursor-1'));
      await t.pumpAndSettle();
      expect(find.text('¿Revocar Cursor?'), findsOneWidget);
      await t.tap(find.byKey(_confirm));
      await t.pumpAndSettle();
      expect(assistants.revokes, ['cursor-1']);
      expect(_row('cursor-1'), findsNothing);
      expect(_row('claude'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('closing the question revokes nothing', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, assistants: assistants);
      await t.tap(_revoke('claude'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(assistants.revokes, isEmpty);
      expect(_revoke('claude'), findsOneWidget);
    });

    testPage('offline, it says so, keeps the question for another try, and reads the list', (
      t,
    ) async {
      final assistants = FakeAssistantsRepository([_claude()])
        ..revokeFailure = const HomeFailure(0);
      await _pump(t, assistants: assistants);
      final before = assistants.lists;
      await t.tap(_revoke('claude'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(_confirm));
      await t.pumpAndSettle();
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(find.byKey(_confirm), findsOneWidget);
      expect(assistants.lists, before + 1, reason: 'refreshed even on failure');
      await t.tap(find.byKey(_confirm));
      await t.pumpAndSettle();
      expect(assistants.revokes, [_claudeId, _claudeId]);
      expect(_connect('claude'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('coming back to the app', () {
    Future<void> background(WidgetTester t) async {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
    }

    testPage('reads the list again and says once that a new app got connected', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, assistants: assistants);
      expect(find.textContaining('quedó conectado'), findsNothing, reason: 'not on first load');
      final before = assistants.lists;

      assistants.items.add(_chatGpt());
      await background(t);
      expect(assistants.lists, before + 1);
      expect(find.text('ChatGPT quedó conectado.'), findsOneWidget);
      expect(_revoke('chatgpt'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await t.pumpAndSettle();
      expect(find.text('ChatGPT quedó conectado.'), findsNothing);

      await background(t);
      expect(assistants.lists, before + 2);
      expect(find.text('ChatGPT quedó conectado.'), findsNothing, reason: 'said once');
      await t.pump(const Duration(seconds: 10));
    });

    testPage('another client getting connected is not announced', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, assistants: assistants);
      assistants.items.add(_cursor());
      await background(t);
      expect(_row('cursor-1'), findsOneWidget);
      expect(find.textContaining('quedó conectado'), findsNothing);
    });
  });

  group('a guest', () {
    testPage('is told to add an email first: no Conectar, no list', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, guest: true, assistants: assistants);
      expect(said('Primero agrega un email'), findsWidgets);
      expect(
        said('Primero guarda tu progreso con un correo; después podrás conectar un asistente.'),
        findsOneWidget,
      );
      expect(_connect('claude'), findsNothing);
      expect(_row('claude'), findsNothing);
      expect(assistants.lists, 0, reason: 'the server refuses a guest; it is not asked');
    });
  });

  group('an encrypted account', () {
    testPage('sees the list, the address, and revokes, as any account', (t) async {
      final assistants = FakeAssistantsRepository([_claude(), _chatGpt()]);
      await _pump(t, assistants: assistants, overrides: previewOpen());
      expect(_revoke('claude'), findsOneWidget);
      expect(find.byKey(const Key('settings.assistants.comingSoon')), findsNothing);
      await t.tap(_revoke('claude'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(_confirm));
      await t.pumpAndSettle();
      expect(assistants.revokes, [_claudeId]);
      expect(_connect('claude'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('a session that changed hands: nothing revoked, the gate checks who is in', (t) async {
      final gate = _Gate();
      final assistants = FakeAssistantsRepository([_claude()])
        ..revokeFailure = const HomeFailure(409, code: 'session_changed');
      await _pump(
        t,
        assistants: assistants,
        overrides: [...previewOpen(), vaultGateProvider.overrideWithValue(gate)],
      );
      await t.tap(_revoke('claude'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(_confirm));
      await t.pumpAndSettle();
      expect(gate.changed, 1);
      expect(find.text('Revocamos Claude.'), findsNothing);
      expect(find.byKey(_confirm), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('a guest is told to add an email and the list is not read', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, guest: true, assistants: assistants, overrides: previewOpen());
      expect(said('Primero agrega un email'), findsWidgets);
      expect(_connect('claude'), findsNothing);
      expect(assistants.lists, 0);
    });
  });
}

/// The open vault's gate, as far as a revoke refused with `session_changed` tells it.
class _Gate implements AppVaultGate {
  int changed = 0;

  @override
  void sessionChanged() => changed++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
