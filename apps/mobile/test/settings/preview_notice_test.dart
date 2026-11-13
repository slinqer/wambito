// An encrypted (`preview`) account: export, import and the assistants wait for encryption. Each
// shows "Próximamente con cifrado" in place of its action, and nothing of it reaches the server
// (fake repositories record zero calls).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/files/files_channel.dart';
import 'package:wambito/settings/account_repository.dart';
import 'package:wambito/settings/assistants_repository.dart';

import '../import/fakes.dart';
import '../import/import_test.dart' show pumpImport;
import '../support/preview_account.dart';
import 'account_harness.dart';
import 'fakes.dart';
import 'harness.dart';

Finder said(String part) => find.bySemanticsLabel(RegExp(RegExp.escape(part)));

Future<void> _show(WidgetTester t, String key) async {
  await t.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

void main() {
  group('export', () {
    testWidgets('says it waits for encryption, with no button, and asks the server nothing', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final accounts = FakeAccountRepository();
      await pumpSettingsApp(
        t,
        location: '/settings',
        overrides: [
          ...previewOpen(),
          accountRepositoryProvider.overrideWithValue(accounts),
          filesChannelProvider.overrideWithValue(FakeFilesChannel()),
        ],
      );
      await _show(t, 'settings.export.comingSoon');
      expect(said('Próximamente con cifrado'), findsWidgets);
      expect(find.byKey(const Key('settings.export.json')), findsNothing);
      expect(find.byKey(const Key('settings.export.csv')), findsNothing);
      expect(accounts.exports, isEmpty);
      handle.dispose();
    });

    testWidgets('a plain account keeps both buttons', (t) async {
      await pumpAccount(t);
      await _show(t, 'settings.export.json');
      expect(find.byKey(const Key('settings.export.comingSoon')), findsNothing);
    });
  });

  group('import', () {
    testWidgets('Settings shows the notice in place of the link to the import', (t) async {
      final handle = t.ensureSemantics();
      await pumpSettingsApp(t, location: '/settings', overrides: previewOpen());
      await _show(t, 'settings.import.comingSoon');
      expect(said('Próximamente con cifrado'), findsWidgets);
      expect(find.byKey(const Key('settings.import')), findsNothing);
      handle.dispose();
    });

    testWidgets('the import page says it waits, offers no picker and asks the server nothing', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final env = await pumpImport(t, overrides: previewOpen());
      expect(find.byKey(const Key('import.page')), findsOneWidget);
      expect(find.byKey(const Key('import.comingSoon')), findsOneWidget);
      expect(said('Próximamente con cifrado'), findsWidgets);
      expect(find.byKey(const Key('import.choose')), findsNothing);
      expect(find.byKey(const Key('import.budgets')), findsNothing);
      expect(env.server.calls, isEmpty);
      expect(env.files.next, isNotNull, reason: 'no picker was opened');
      handle.dispose();
    });
  });

  group('due notice', () {
    testWidgets('Settings shows the notice in place of the "Hoy vence…" switch', (t) async {
      final handle = t.ensureSemantics();
      await pumpSettingsApp(t, location: '/settings', overrides: previewOpen());
      await _show(t, 'settings.dueNotice.comingSoon');
      expect(said('Próximamente con cifrado'), findsWidgets);
      expect(find.byKey(const Key('settings.dueNotice')), findsNothing);
      handle.dispose();
    });
  });

  group('assistants', () {
    testWidgets('no address to connect and no list: the notice, and the list is never read', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final assistants = FakeAssistantsRepository();
      await pumpSettingsApp(
        t,
        location: '/settings',
        overrides: <Override>[
          ...previewOpen(),
          assistantsRepositoryProvider.overrideWithValue(assistants),
        ],
      );
      await _show(t, 'settings.assistants.comingSoon');
      expect(said('Próximamente con cifrado'), findsWidgets);
      expect(find.byKey(const Key('settings.assistants.url')), findsNothing);
      expect(find.byKey(const Key('settings.assistants.copy')), findsNothing);
      expect(assistants.lists, 0);
      expect(assistants.revokes, isEmpty);
      handle.dispose();
    });
  });
}
