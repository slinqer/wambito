// Deleting the account (apps/web/app/features/settings/DeleteAccount.tsx) and Review Focus 5 of
// Stage 3c: the account goes, and so does everything of it the phone kept (the session, the home
// cache, the widget's figures, the notices, the voice models, the welcome's draft, the answers
// to the passkey offer). A delete that fails changes nothing and says why.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/settings/account_deletion.dart';
import 'package:wambito/settings/account_repository.dart';
import 'package:wambito/ui/press_button.dart';

import '../home/fakes.dart';
import 'account_harness.dart';

Finder _said(String text) => find.bySemanticsLabel(text);

Future<void> _openSheet(WidgetTester t) async {
  await scrollToKey(t, 'settings.delete');
  await t.tap(find.byKey(const Key('settings.delete')));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('settings.delete.field')), text);
  await t.pumpAndSettle();
}

bool _confirmOn(WidgetTester t) =>
    t.widget<PressButton>(find.byKey(const Key('settings.delete.confirm'))).onPressed != null;

Future<void> _confirm(WidgetTester t) async {
  await t.tap(find.byKey(const Key('settings.delete.confirm')));
  await t.pumpAndSettle();
}

/// What the phone still holds of the account.
Future<({bool session, bool cache, bool widgetFigures, bool voice})> _held(AccountEnv env) async =>
    (
      session: await SessionStore().read() != null,
      cache: env.cache.value != null,
      widgetFigures: !widgetSignedOut(env.widgets),
      voice: env.app.models.installed,
    );

void main() {
  group('the card', () {
    testWidgets('is a red row at the foot: its title, one line, and it opens the sheet', (t) async {
      final handle = t.ensureSemantics();
      await pumpAccount(t);
      await scrollToKey(t, 'settings.delete');
      expect(find.text('Borra tu cuenta y tus movimientos'), findsOneWidget);
      expect(find.text('Eliminar tu cuenta'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('opens the sheet: what goes, the export first, the email field, two buttons', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await pumpAccount(t);
      await _openSheet(t);
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      expect(
        _said(
          'Se borran de inmediato tus movimientos, categorías, presupuestos, recurrentes y huellas. Las copias de seguridad que los incluyan se borran solas en 14 días.',
        ),
        findsOneWidget,
      );
      expect(find.text('DESCARGA TUS DATOS ANTES'), findsOneWidget);
      expect(_said('Escribe tu correo para confirmar'), findsWidgets);
      expect(_said('Tu correo es ana@example.com.'), findsOneWidget);
      expect(find.text('SÍ, ELIMINAR MI CUENTA'), findsOneWidget);
      expect(find.text('CANCELAR'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('speaks English with the web\'s English', (t) async {
      await pumpAccount(t, locale: const Locale('en'));
      await _openSheet(t);
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.text('YES, DELETE MY ACCOUNT'), findsOneWidget);
      expect(find.text('DOWNLOAD YOUR DATA FIRST'), findsOneWidget);
    });
  });

  group('the email', () {
    testWidgets('unlocks the button only when it is typed exactly (case and spaces apart)', (
      t,
    ) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      expect(_confirmOn(t), isFalse);
      await _type(t, 'ana@example.co');
      expect(_confirmOn(t), isFalse);
      await _type(t, 'otra@example.com');
      expect(_confirmOn(t), isFalse);
      await _type(t, 'ana @example.com');
      expect(_confirmOn(t), isFalse);
      await _type(t, '  ANA@Example.com ');
      expect(_confirmOn(t), isTrue);
      expect(env.accounts.deletes, 0);
    });

    testWidgets('Enter deletes only once it matches', (t) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      await _type(t, 'ana@example.co');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(env.accounts.deletes, 0);
      expect(_confirmOn(t), isFalse);
      await _type(t, 'ana@example.com');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(env.accounts.deletes, 1);
    });

    testWidgets('cancelling closes the sheet and forgets what was typed', (t) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await t.tap(find.text('CANCELAR'));
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar tu cuenta?'), findsNothing);
      await t.tap(find.byKey(const Key('settings.delete')));
      await t.pumpAndSettle();
      expect(_confirmOn(t), isFalse);
      expect(env.accounts.deletes, 0);
    });
  });

  group('the delete', () {
    testWidgets('deletes once however many taps and Enters come, saying so while it goes', (
      t,
    ) async {
      final env = await pumpAccount(t);
      env.accounts.holdDelete = Completer<void>();
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await t.tap(find.byKey(const Key('settings.delete.confirm')));
      await t.pump();
      expect(find.text('ELIMINANDO…'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.delete.confirm')), warnIfMissed: false);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      // Neither way out works meanwhile.
      expect(
        t.widget<PressButton>(find.byKey(const Key('settings.delete.cancel'))).onPressed,
        isNull,
      );
      expect(env.accounts.deletes, 1);
      env.accounts.holdDelete!.complete();
      await t.pumpAndSettle();
      expect(env.accounts.deletes, 1);
    });

    testWidgets('signs out and lands on the entry screen', (t) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      expect(env.accounts.deletes, 1);
      expect(env.app.stored, isNull);
      expect(env.app.container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(find.byKey(const Key('entry.start')), findsOneWidget);
      expect(find.text('¿Eliminar tu cuenta?'), findsNothing);
    });

    testWidgets('does not ask the server to end a session its deletion already took', (t) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      expect(env.app.auth.calls.where((c) => c.startsWith('signOut')), isEmpty);
    });
  });

  group('Review Focus 5: what the phone keeps goes with the account', () {
    testWidgets('the session, the home cache and the widget\'s figures', (t) async {
      final env = await pumpAccount(t);
      final before = await _held(env);
      expect((before.session, before.cache, before.widgetFigures), (true, true, true));
      final updates = env.widgets.updates;
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      final after = await _held(env);
      expect(after.session, isFalse);
      expect(after.cache, isFalse);
      // The widget says "Abre Wambito para empezar", with no figure of anyone, and was told to redraw.
      expect(widgetSignedOut(env.widgets), isTrue);
      expect(env.widgets.updates, greaterThan(updates));
      expect(after.widgetFigures, isFalse);
    });

    testWidgets('the notice jobs, and any notice already posted', (t) async {
      final env = await pumpAccount(t);
      env.platform.clear();
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      // Cancelling a job also takes its posted notice off the shade (NoticeScheduler.cancelDue).
      expect(env.platform.callsNamed('cancelDue'), isNotEmpty);
      expect(env.platform.callsNamed('cancelGuest'), isNotEmpty);
      expect(env.platform.callsNamed('scheduleDue'), isEmpty);
      expect(env.platform.callsNamed('scheduleGuest'), isEmpty);
    });

    testWidgets('the voice models', (t) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      expect(env.app.models.deletes, 1);
      expect(env.app.models.installed, isFalse);
    });

    testWidgets('the welcome\'s draft, the passkey offer\'s answer and the unlock hint, of this '
        'account only', (t) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      final kept = env.app.settings.values;
      expect(kept.containsKey('onboarding.draft.user-1'), isFalse);
      expect(kept['onboarding.draft.other'], '{"currency":"USD"}');
      expect(jsonDecode(kept['passkey.offered']!), ['other']);
      expect(kept.containsKey('wambito.unlock.no_prf.user-1'), isFalse);
      expect(kept['wambito.unlock.no_prf.other'], '1');
    });

    testWidgets('the cards put away on home', (t) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      expect(await env.app.flags['home.dismissed.user-1.budgets']!.read(), isNull);
      expect(await env.app.flags['home.dismissed.user-1.import']!.read(), isNull);
      expect(await env.app.flags['home.dismissed.other.budgets']!.read(), isTrue);
    });

    testWidgets('a step that fails does not stop the rest, nor the sign-out', (t) async {
      final env = await pumpAccount(t);
      env.app.models.deleteFailure = StateError('disk');
      env.cache.failure = StateError('keystore');
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      expect(env.app.stored, isNull);
      expect(widgetSignedOut(env.widgets), isTrue);
      expect(env.platform.callsNamed('cancelDue'), isNotEmpty);
      expect(find.byKey(const Key('entry.start')), findsOneWidget);
    });
  });

  testWidgets('a copy made for the share sheet does not outlive the account', (t) async {
    final env = await pumpAccount(t);
    await _openSheet(t);
    await _type(t, 'ana@example.com');
    await _confirm(t);
    expect(env.files.sharedCleared, 1);
    expect(env.app.stored, isNull);
  });

  testWidgets('and a delete that fails leaves them', (t) async {
    final env = await pumpAccount(t);
    env.accounts.deleteFailure = const HomeFailure(503);
    await _openSheet(t);
    await _type(t, 'ana@example.com');
    await _confirm(t);
    expect(env.files.sharedCleared, 0);
    await t.pump(const Duration(seconds: 10));
  });

  group('a delete that fails', () {
    Future<AccountEnv> failing(WidgetTester t, Object failure) async {
      final env = await pumpAccount(t);
      env.accounts.deleteFailure = failure;
      env.platform.clear();
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await _confirm(t);
      return env;
    }

    Future<void> expectEverythingKept(WidgetTester t, AccountEnv env) async {
      final held = await _held(env);
      expect(held.session, isTrue);
      expect(held.cache, isTrue);
      expect(held.widgetFigures, isTrue);
      expect(held.voice, isTrue);
      expect(env.app.stored, isNotNull);
      expect(env.platform.callsNamed('cancelDue'), isEmpty);
      expect(env.app.settings.values.containsKey('onboarding.draft.user-1'), isTrue);
      expect(jsonDecode(env.app.settings.values['passkey.offered']!), ['user-1', 'other']);
      // The sheet is still there, with the email typed, for another try.
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      expect(_confirmOn(t), isTrue);
    }

    testWidgets('a server error: the sheet says why, as an alert, and nothing changes', (t) async {
      final handle = t.ensureSemantics();
      final env = await failing(t, const HomeFailure(503, code: 'internal_error'));
      final message = find.byKey(const Key('settings.delete.error'));
      expect(message, findsOneWidget);
      expect(
        _said('Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
      handle.dispose();
      await expectEverythingKept(t, env);
    });

    testWidgets('no connection: the web\'s words, and nothing changes', (t) async {
      final handle = t.ensureSemantics();
      final env = await failing(t, const HomeFailure(0));
      expect(_said('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      handle.dispose();
      await expectEverythingKept(t, env);
    });

    testWidgets('trying again after a failure deletes, and clears the message on the way', (
      t,
    ) async {
      final env = await failing(t, const HomeFailure(503, code: 'internal_error'));
      await _confirm(t);
      expect(env.accounts.deletes, 2);
      expect(env.app.stored, isNull);
      expect(find.byKey(const Key('entry.start')), findsOneWidget);
    });

    testWidgets(
      'a 401 on the first try is an expired session: signed out, the account NOT deleted, and it says so',
      (t) async {
        final env = await failing(t, const HomeFailure(401));
        // Signed out, and nothing else of the phone was cleared as for a delete.
        expect(env.app.stored, isNull);
        expect(find.byKey(const Key('entry.start')), findsOneWidget);
        expect(find.text('¿Eliminar tu cuenta?'), findsNothing);
        expect(env.app.models.installed, isTrue);
        expect(env.app.settings.values.containsKey('onboarding.draft.user-1'), isTrue);
        expect(jsonDecode(env.app.settings.values['passkey.offered']!), ['user-1', 'other']);
        expect(env.accounts.deletes, 1);
        // And the person is told plainly that the account is still there.
        expect(
          find.text(
            'Tu sesión había vencido, así que tu cuenta NO se eliminó. Entra de nuevo y vuelve a intentarlo.',
          ),
          findsOneWidget,
        );
        await t.pump(const Duration(seconds: 10));
      },
    );

    testWidgets(
      'a 401 after an attempt that lost its answer means the account is gone: cleared as after a delete',
      (t) async {
        final env = await failing(t, const HomeFailure(0));
        // The answer was lost; the retry finds the session gone, because the account is.
        env.accounts.deleteFailure = const HomeFailure(401);
        await _confirm(t);
        expect(env.accounts.deletes, 2);
        expect(env.app.stored, isNull);
        expect(widgetSignedOut(env.widgets), isTrue);
        expect(env.app.models.installed, isFalse);
        expect(env.app.settings.values.containsKey('onboarding.draft.user-1'), isFalse);
        expect(find.byKey(const Key('entry.start')), findsOneWidget);
        expect(find.textContaining('NO se eliminó'), findsNothing);
      },
    );
  });

  group('while the DELETE is on its way the sheet stays', () {
    Future<AccountEnv> busy(WidgetTester t) async {
      final env = await pumpAccount(t);
      env.accounts.holdDelete = Completer<void>();
      await _openSheet(t);
      await _type(t, 'ana@example.com');
      await t.tap(find.byKey(const Key('settings.delete.confirm')));
      await t.pump();
      expect(find.text('ELIMINANDO…'), findsOneWidget);
      return env;
    }

    testWidgets('a tap outside, a drag down, Escape and the back button do nothing', (t) async {
      final env = await busy(t);
      // Outside: the backdrop above the sheet.
      await t.tapAt(const Offset(195, 60));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      // A drag down from the sheet's title, and a fling.
      await t.fling(find.text('¿Eliminar tu cuenta?'), const Offset(0, 600), 2000);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      // There is no "Cerrar" to press either.
      expect(find.text('CERRAR'), findsNothing);
      expect(env.accounts.deletes, 1);
      env.accounts.holdDelete!.complete();
      await t.pumpAndSettle();
    });

    testWidgets('a failure after a slow answer reaches the person, and the sheet is theirs again', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final env = await busy(t);
      env.accounts.deleteFailure = const HomeFailure(503, code: 'internal_error');
      env.accounts.holdDelete!.complete();
      await t.pumpAndSettle();
      expect(
        _said('Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      expect(_confirmOn(t), isTrue);
      // Free again: the back button closes it, as before.
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar tu cuenta?'), findsNothing);
      handle.dispose();
    });

    testWidgets('a sheet that is closed by the app anyway still says a failure', (t) async {
      final env = await busy(t);
      // Something other than the person closes it (a link opening a page, say).
      Navigator.of(
        t.element(find.byKey(const Key('settings.delete.field'))),
        rootNavigator: true,
      ).pop();
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar tu cuenta?'), findsNothing);
      env.accounts.deleteFailure = const HomeFailure(0);
      env.accounts.holdDelete!.complete();
      await t.pumpAndSettle();
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets(
      'a second request meanwhile gets the same answer: one DELETE, never a false success',
      (t) async {
        final env = await pumpAccount(t);
        env.accounts.holdDelete = Completer<void>();
        env.accounts.deleteFailure = const HomeFailure(503);
        final deletion = env.app.container.read(accountDeletionProvider);
        final first = deletion.delete();
        final second = deletion.delete();
        env.accounts.holdDelete!.complete();
        await expectLater(first, throwsA(isA<HomeFailure>()));
        await expectLater(second, throwsA(isA<HomeFailure>()));
        expect(env.accounts.deletes, 1);
        expect(env.app.stored, isNotNull);
      },
    );

    testWidgets('"Descarga tus datos antes" is off too: no export of an account being deleted', (
      t,
    ) async {
      final env = await busy(t);
      expect(
        t.widget<PressButton>(find.byKey(const Key('settings.delete.export'))).onPressed,
        isNull,
      );
      await t.tap(find.byKey(const Key('settings.delete.export')), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(env.accounts.exports, isEmpty);
      env.accounts.holdDelete!.complete();
      await t.pumpAndSettle();
    });

    testWidgets('at rest the sheet still closes by a tap outside and by back', (t) async {
      await pumpAccount(t);
      await _openSheet(t);
      await t.tapAt(const Offset(195, 60));
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar tu cuenta?'), findsNothing);
      await t.tap(find.byKey(const Key('settings.delete')));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar tu cuenta?'), findsNothing);
    });
  });

  group('the export first', () {
    testWidgets('"Descarga tus datos antes" exports the JSON and asks what to do with it', (
      t,
    ) async {
      final env = await pumpAccount(t);
      await _openSheet(t);
      await t.tap(find.byKey(const Key('settings.delete.export')));
      await t.pumpAndSettle();
      expect(env.accounts.exports, [ExportFormat.json]);
      expect(find.text('Tu archivo está listo'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.export.save')));
      await t.pumpAndSettle();
      expect(env.files.saved.single.$1, 'wambito-export-2026-10-21.json');
      // Back at the deletion's sheet, with the account untouched.
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      expect(env.accounts.deletes, 0);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('a guest', () {
    testWidgets('has the row, off, with why: an email comes first', (t) async {
      final handle = t.ensureSemantics();
      final env = await pumpAccount(t, guest: true);
      await scrollToKey(t, 'settings.delete');
      expect(
        _said('Primero guarda tu progreso con un correo; después podrás eliminar tu cuenta.'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('settings.delete')), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar tu cuenta?'), findsNothing);
      expect(env.accounts.deletes, 0);
      handle.dispose();
    });
  });
}
