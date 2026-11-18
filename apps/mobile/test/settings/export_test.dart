// "Tus datos" in Settings: the export (apps/web/app/features/settings/use-export.ts). The web hands
// the file to the browser's download; the phone asks what to do with it (save it where the person
// chooses, or share it) and hands it to the files channel (lib/files).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/files/files_channel.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/settings/account_repository.dart';
import 'package:wambito/ui/press_button.dart';

import 'account_harness.dart';

Finder _said(String text) => find.bySemanticsLabel(text);

Future<void> _tapExport(WidgetTester t, String format) async {
  await scrollToKey(t, 'settings.export.$format');
  await t.tap(find.byKey(Key('settings.export.$format')));
  await t.pumpAndSettle();
}

void main() {
  group('the buttons', () {
    testWidgets('are the web\'s: under the import, JSON and CSV, with what each gives', (t) async {
      final handle = t.ensureSemantics();
      await pumpAccount(t);
      await scrollToKey(t, 'settings.export.json');
      expect(_said('Tus datos'), findsWidgets);
      expect(_said('Descarga tus datos'), findsOneWidget);
      expect(
        _said('Todo en JSON, o tus movimientos en CSV para abrirlos en Excel o Google Sheets.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings.export.json')), findsOneWidget);
      expect(find.byKey(const Key('settings.export.csv')), findsOneWidget);
      expect(find.text('DESCARGAR JSON'), findsOneWidget);
      expect(find.text('DESCARGAR CSV'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('are in English, with the web\'s words', (t) async {
      await pumpAccount(t, locale: const Locale('en'));
      await scrollToKey(t, 'settings.export.json');
      expect(find.text('DOWNLOAD JSON'), findsOneWidget);
      expect(find.text('DOWNLOAD CSV'), findsOneWidget);
    });
  });

  group('saving', () {
    testWidgets('JSON asks the server for JSON, then offers to save or share the file by name', (
      t,
    ) async {
      final env = await pumpAccount(t);
      await _tapExport(t, 'json');
      expect(env.accounts.exports, [ExportFormat.json]);
      expect(find.text('Tu archivo está listo'), findsOneWidget);
      expect(find.text('¿Qué hacemos con wambito-export-2026-10-21.json?'), findsOneWidget);
      expect(find.byKey(const Key('settings.export.save')), findsOneWidget);
      expect(find.byKey(const Key('settings.export.share')), findsOneWidget);
      // Nothing is written or sent before the person chooses.
      expect(env.files.saved, isEmpty);
      expect(env.files.shared, isEmpty);
    });

    testWidgets(
      '"Guardar en el teléfono" gives the bytes, the name and the type to the save picker',
      (t) async {
        final env = await pumpAccount(t);
        await _tapExport(t, 'json');
        await t.tap(find.byKey(const Key('settings.export.save')));
        await t.pumpAndSettle();
        final (name, bytes, mime) = env.files.saved.single;
        expect(name, 'wambito-export-2026-10-21.json');
        expect(mime, 'application/json');
        expect(utf8.decode(bytes), '{"user":{"id":"user-1"}}');
        expect(env.files.shared, isEmpty);
        expect(find.text('Listo: guardamos wambito-export-2026-10-21.json.'), findsOneWidget);
        // The question is gone.
        expect(find.text('Tu archivo está listo'), findsNothing);
        await t.pump(const Duration(seconds: 10));
      },
    );

    testWidgets('CSV is asked as CSV and saved as text/csv', (t) async {
      final env = await pumpAccount(t);
      await _tapExport(t, 'csv');
      expect(env.accounts.exports, [ExportFormat.csv]);
      await t.tap(find.byKey(const Key('settings.export.save')));
      await t.pumpAndSettle();
      final (name, bytes, mime) = env.files.saved.single;
      expect(name, 'wambito-export-2026-10-21.csv');
      expect(mime, 'text/csv');
      expect(utf8.decode(bytes), startsWith('date,name,amount'));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('closing the save picker says nothing and leaves the page as it was', (t) async {
      final env = await pumpAccount(t);
      env.files.saveAnswer = false;
      await _tapExport(t, 'json');
      await t.tap(find.byKey(const Key('settings.export.save')));
      await t.pumpAndSettle();
      expect(env.files.saved, hasLength(1));
      expect(find.textContaining('Listo: guardamos'), findsNothing);
      expect(find.byKey(const Key('settings.export.json')), findsOneWidget);
    });

    testWidgets('a save that fails says so, in a toast', (t) async {
      final env = await pumpAccount(t);
      env.files.saveFailure = const FilesFailure(FilesFailureKind.unreadable);
      await _tapExport(t, 'json');
      await t.tap(find.byKey(const Key('settings.export.save')));
      await t.pumpAndSettle();
      expect(find.text('No pudimos guardar el archivo. Inténtalo otra vez.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('sharing', () {
    testWidgets('"Compartir" hands the file to the share sheet', (t) async {
      final env = await pumpAccount(t);
      await _tapExport(t, 'csv');
      await t.tap(find.byKey(const Key('settings.export.share')));
      await t.pumpAndSettle();
      final (name, bytes, mime) = env.files.shared.single;
      expect(name, 'wambito-export-2026-10-21.csv');
      expect(mime, 'text/csv');
      expect(utf8.decode(bytes), contains('Arriendo'));
      expect(env.files.saved, isEmpty);
      // The share sheet is the feedback: no toast.
      expect(find.textContaining('Listo'), findsNothing);
    });

    testWidgets('a phone with nothing to share with says so', (t) async {
      final env = await pumpAccount(t);
      env.files.shareFailure = const FilesFailure(FilesFailureKind.unavailable);
      await _tapExport(t, 'json');
      await t.tap(find.byKey(const Key('settings.export.share')));
      await t.pumpAndSettle();
      expect(find.text('No encontramos una app para compartir el archivo.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('when it does not go', () {
    testWidgets('a cancelled question saves and shares nothing', (t) async {
      final env = await pumpAccount(t);
      await _tapExport(t, 'json');
      await t.tap(find.text('CANCELAR'));
      await t.pumpAndSettle();
      expect(env.files.saved, isEmpty);
      expect(env.files.shared, isEmpty);
      expect(find.text('Tu archivo está listo'), findsNothing);
    });

    testWidgets('a failed export is the web\'s toast, and no file', (t) async {
      final env = await pumpAccount(t);
      env.accounts.exportFailure = const HomeFailure(503, code: 'internal_error');
      await _tapExport(t, 'json');
      expect(
        find.text('Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
      expect(find.text('Tu archivo está listo'), findsNothing);
      expect(env.files.saved, isEmpty);
      // The buttons are back for another try.
      expect(
        t.widget<PressButton>(find.byKey(const Key('settings.export.json'))).onPressed,
        isNotNull,
      );
      expect(
        t.widget<PressButton>(find.byKey(const Key('settings.export.csv'))).onPressed,
        isNotNull,
      );
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('a 401 is a session the server no longer knows: signed out, as everywhere else', (
      t,
    ) async {
      final env = await pumpAccount(t);
      env.accounts.exportFailure = const HomeFailure(401);
      await _tapExport(t, 'json');
      expect(env.app.stored, isNull);
      expect(find.byKey(const Key('entry.start')), findsOneWidget);
      expect(find.text('Tu archivo está listo'), findsNothing);
      expect(env.files.saved, isEmpty);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('offline says so', (t) async {
      final env = await pumpAccount(t);
      env.accounts.exportFailure = const HomeFailure(0);
      await _tapExport(t, 'csv');
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('while one is being prepared both buttons are off, and a second tap asks nothing', (
      t,
    ) async {
      final env = await pumpAccount(t);
      env.accounts.holdExport = Completer<void>();
      await scrollToKey(t, 'settings.export.json');
      await t.tap(find.byKey(const Key('settings.export.json')));
      await t.pump();
      await t.tap(find.byKey(const Key('settings.export.json')), warnIfMissed: false);
      await t.tap(find.byKey(const Key('settings.export.csv')), warnIfMissed: false);
      await t.pump();
      expect(env.accounts.exports, [ExportFormat.json]);
      env.accounts.holdExport!.complete();
      await t.pumpAndSettle();
      expect(find.text('Tu archivo está listo'), findsOneWidget);
    });
  });

  group('a guest', () {
    testWidgets('sees both buttons off, with why: an email comes first', (t) async {
      final handle = t.ensureSemantics();
      final env = await pumpAccount(t, guest: true);
      await scrollToKey(t, 'settings.export.json');
      expect(
        _said('Primero guarda tu progreso con un correo; después podrás descargar tus datos.'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('settings.export.json')), warnIfMissed: false);
      await t.tap(find.byKey(const Key('settings.export.csv')), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(env.accounts.exports, isEmpty);
      handle.dispose();
    });
  });
}
