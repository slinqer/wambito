// "Conecta tu asistente" in Settings (spec §6.2): the MCP's address with its copy button, where Claude
// and ChatGPT take it, two things to ask, and the connected assistants, each revoked after asking.
// A guest sees a note to save their progress instead of the list. An encrypted (`preview`) account
// sees the same: the server's MCP opens its data on the consent page.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/server_url.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/router.dart';
import 'package:wambito/settings/assistants_repository.dart';
import 'package:wambito/settings/initial_settings.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../support/preview_account.dart';

import '../home/fakes.dart';
import 'fakes.dart';
import 'harness.dart';

final _now = DateTime.utc(2026, 10, 31, 15);

const _claudeId = 'https://claude.ai/oauth/mcp-oauth-client-metadata';

ConnectedAssistant _claude() => ConnectedAssistant(
  clientId: _claudeId,
  name: 'Claude',
  domain: 'claude.ai',
  connectedAt: DateTime.utc(2026, 10, 30, 14),
  lastUsedAt: DateTime.utc(2026, 10, 31, 9),
);

ConnectedAssistant _chatGpt() => ConnectedAssistant(
  clientId: 'chatgpt-1',
  name: 'ChatGPT',
  domain: 'chatgpt.com',
  // 02:00 UTC is still the day before in Bogota.
  connectedAt: DateTime.utc(2026, 10, 29, 2),
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

/// A text drawn by `CssParagraph`: found by what a screen reader reads.
Finder said(String text) => find.bySemanticsLabel(text);

Future<void> _scrollTo(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

Finder _row(String clientId) => find.byKey(Key('settings.assistants.row.$clientId'));

/// The open vault's gate, as far as a revoke refused with `session_changed` tells it.
class _Gate implements AppVaultGate {
  int changed = 0;

  @override
  void sessionChanged() => changed++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('how to connect', () {
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

    testPage('shows the MCP\'s address, the steps for Claude and ChatGPT, and two requests', (
      t,
    ) async {
      final env = await _pump(t, assistants: FakeAssistantsRepository());
      await _scrollTo(t, find.byKey(const Key('settings.assistants.copy')));
      final url = mcpUrl(env.container.read(serverUrlProvider)).toString();
      expect(url, endsWith('/mcp'));
      expect(find.text(url), findsOneWidget);
      expect(said('Conecta tu asistente'), findsWidgets);
      expect(
        said(
          'En Claude: Ajustes → Conectores → Añadir conector personalizado, y pega la dirección.',
        ),
        findsOneWidget,
      );
      expect(
        said(
          'En ChatGPT: Ajustes → Conectores, si tu plan lo permite; crea uno con esta dirección.',
        ),
        findsOneWidget,
      );
      expect(said('«anota 18 lukas en almuerzo»'), findsOneWidget);
      expect(said('«¿cómo voy este mes?»'), findsOneWidget);
    });

    testPage('the address follows the server the app talks to', (t) async {
      await _pump(
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
      expect(find.text('https://wambito.example.test/mcp'), findsOneWidget);
    });

    testPage('copies the address, and says so', (t) async {
      final env = await _pump(t, assistants: FakeAssistantsRepository());
      await _scrollTo(t, find.byKey(const Key('settings.assistants.copy')));
      expect(find.bySemanticsLabel('Copiar la dirección del conector'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.assistants.copy')));
      await t.pumpAndSettle();
      expect(clipboard, mcpUrl(env.container.read(serverUrlProvider)).toString());
      expect(find.text('Copiamos la dirección.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('the connected assistants', () {
    testPage('lists each: its name, where it comes from, when connected and last used', (t) async {
      await _pump(t, assistants: FakeAssistantsRepository([_claude(), _chatGpt()]));
      await _scrollTo(t, find.byKey(const Key('settings.assistants.revoke.chatgpt-1')));
      final claude = _row(_claudeId);
      expect(find.descendant(of: claude, matching: find.text('Claude')), findsOneWidget);
      expect(find.descendant(of: claude, matching: find.text('claude.ai')), findsOneWidget);
      expect(
        find.descendant(of: claude, matching: find.text('Conectado el 30 oct 2026')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: claude, matching: find.text('Último uso el 31 oct 2026')),
        findsOneWidget,
      );
      final chatGpt = _row('chatgpt-1');
      expect(find.descendant(of: chatGpt, matching: find.text('ChatGPT')), findsOneWidget);
      expect(find.descendant(of: chatGpt, matching: find.text('chatgpt.com')), findsOneWidget);
      expect(
        find.descendant(of: chatGpt, matching: find.text('Conectado el 28 oct 2026')),
        findsOneWidget,
        reason: 'in Bogota\'s day',
      );
      expect(find.descendant(of: chatGpt, matching: find.text('Aún sin usar')), findsOneWidget);
      expect(find.bySemanticsLabel('Revocar Claude'), findsOneWidget);
      expect(find.bySemanticsLabel('Revocar ChatGPT'), findsOneWidget);
    });

    testPage('says when there are none', (t) async {
      await _pump(t, assistants: FakeAssistantsRepository());
      await _scrollTo(t, said('Aún no conectas ningún asistente.'));
      expect(said('Aún no conectas ningún asistente.'), findsOneWidget);
    });

    testPage('says when the list cannot be read', (t) async {
      final assistants = FakeAssistantsRepository()..listFailure = const HomeFailure(0);
      await _pump(t, assistants: assistants);
      final failed = said('No pudimos cargar tus asistentes. Inténtalo de nuevo en un momento.');
      await _scrollTo(t, failed);
      expect(failed, findsOneWidget);
    });

    testPage('Revocar asks first, then revokes and takes the row out', (t) async {
      final assistants = FakeAssistantsRepository([_claude(), _chatGpt()]);
      await _pump(t, assistants: assistants);
      final revoke = find.byKey(const Key('settings.assistants.revoke.$_claudeId'));
      await _scrollTo(t, revoke);
      await t.tap(revoke);
      await t.pumpAndSettle();
      expect(find.text('¿Revocar Claude?'), findsOneWidget);
      expect(assistants.revokes, isEmpty, reason: 'nothing before the answer');
      await t.tap(find.byKey(const Key('settings.assistants.revoke.confirm')));
      await t.pumpAndSettle();
      expect(assistants.revokes, [_claudeId]);
      expect(find.text('Revocamos Claude.'), findsOneWidget);
      expect(revoke, findsNothing);
      expect(_row(_claudeId), findsNothing);
      expect(_row('chatgpt-1'), findsOneWidget, reason: 'the other one stays');
      await t.pump(const Duration(seconds: 10));
    });

    testPage('closing the question revokes nothing', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, assistants: assistants);
      final revoke = find.byKey(const Key('settings.assistants.revoke.$_claudeId'));
      await _scrollTo(t, revoke);
      await t.tap(revoke);
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(assistants.revokes, isEmpty);
      expect(revoke, findsOneWidget);
    });

    testPage('offline, it says so, keeps the row and the question for another try', (t) async {
      final assistants = FakeAssistantsRepository([_claude()])
        ..revokeFailure = const HomeFailure(0);
      await _pump(t, assistants: assistants);
      final revoke = find.byKey(const Key('settings.assistants.revoke.$_claudeId'));
      await _scrollTo(t, revoke);
      await t.tap(revoke);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings.assistants.revoke.confirm')));
      await t.pumpAndSettle();
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(find.byKey(const Key('settings.assistants.revoke.confirm')), findsOneWidget);
      // The second try goes through.
      await t.tap(find.byKey(const Key('settings.assistants.revoke.confirm')));
      await t.pumpAndSettle();
      expect(assistants.revokes, [_claudeId, _claudeId]);
      expect(revoke, findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('in English', (t) async {
      await _pump(t, locale: const Locale('en'), assistants: FakeAssistantsRepository([_claude()]));
      await _scrollTo(t, find.byKey(const Key('settings.assistants.revoke.$_claudeId')));
      expect(said('Connect your assistant'), findsWidgets);
      expect(find.text('Connected on Oct 30, 2026'), findsOneWidget);
      expect(find.text('Last used on Oct 31, 2026'), findsOneWidget);
      expect(find.bySemanticsLabel('Revoke Claude'), findsOneWidget);
    });
  });

  group('a guest', () {
    testPage('sees how to connect and a note to save their progress, not the list', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, guest: true, assistants: assistants);
      final note = said(
        'Primero guarda tu progreso con un correo; después podrás conectar un asistente.',
      );
      await _scrollTo(t, note);
      expect(note, findsOneWidget);
      expect(find.byKey(const Key('settings.assistants.copy')), findsOneWidget);
      expect(_row(_claudeId), findsNothing);
      expect(said('Asistentes conectados'), findsNothing);
      expect(assistants.lists, 0, reason: 'the server refuses a guest; it is not asked');
    });
  });

  group('an encrypted account', () {
    testPage('sees the address, the steps and the list, as any account', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, assistants: assistants, overrides: previewOpen());
      final revoke = find.byKey(const Key('settings.assistants.revoke.$_claudeId'));
      await _scrollTo(t, revoke);
      expect(find.byKey(const Key('settings.assistants.comingSoon')), findsNothing);
      expect(find.byKey(const Key('settings.assistants.url')), findsOneWidget);
      expect(find.byKey(const Key('settings.assistants.copy')), findsOneWidget);
      expect(
        said(
          'En Claude: Ajustes → Conectores → Añadir conector personalizado, y pega la dirección.',
        ),
        findsOneWidget,
      );
      expect(said('«¿cómo voy este mes?»'), findsOneWidget);
      expect(said('Asistentes conectados'), findsOneWidget);
      expect(
        find.descendant(of: _row(_claudeId), matching: find.text('Conectado el 30 oct 2026')),
        findsOneWidget,
      );
      expect(revoke, findsOneWidget);
      expect(assistants.lists, 1);
    });

    testPage('Revocar asks first, revokes and takes the row out', (t) async {
      final assistants = FakeAssistantsRepository([_claude(), _chatGpt()]);
      await _pump(t, assistants: assistants, overrides: previewOpen());
      final revoke = find.byKey(const Key('settings.assistants.revoke.$_claudeId'));
      await _scrollTo(t, revoke);
      await t.tap(revoke);
      await t.pumpAndSettle();
      expect(find.text('¿Revocar Claude?'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.assistants.revoke.confirm')));
      await t.pumpAndSettle();
      expect(assistants.revokes, [_claudeId]);
      expect(find.text('Revocamos Claude.'), findsOneWidget);
      expect(_row(_claudeId), findsNothing);
      expect(_row('chatgpt-1'), findsOneWidget);
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
      final revoke = find.byKey(const Key('settings.assistants.revoke.$_claudeId'));
      await _scrollTo(t, revoke);
      await t.tap(revoke);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings.assistants.revoke.confirm')));
      await t.pumpAndSettle();
      expect(gate.changed, 1);
      expect(find.text('Revocamos Claude.'), findsNothing);
      expect(find.byKey(const Key('settings.assistants.revoke.confirm')), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('a guest sees the note to save their progress, and the list is not read', (t) async {
      final assistants = FakeAssistantsRepository([_claude()]);
      await _pump(t, guest: true, assistants: assistants, overrides: previewOpen());
      final note = said(
        'Primero guarda tu progreso con un correo; después podrás conectar un asistente.',
      );
      await _scrollTo(t, note);
      expect(note, findsOneWidget);
      expect(find.byKey(const Key('settings.assistants.comingSoon')), findsNothing);
      expect(find.byKey(const Key('settings.assistants.copy')), findsOneWidget);
      expect(_row(_claudeId), findsNothing);
      expect(assistants.lists, 0);
    });
  });
}
