import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/files/files_channel.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/settings/account_deletion.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/vault/vault_gate.dart';
import 'package:wambito/vault/vault_providers.dart';
import 'package:wambito/vault/vault_screen.dart';

import '../support/ui_app.dart';
import 'vault_fakes.dart' show FixedSession, signedIn;

/// The screens of the vault gate (the web's RecoveryKeySetup, Unlock and Locked stories), over a
/// fake gate: what each state shows, what the buttons ask of the gate, and the words.
class FakeGate extends Fake implements AppVaultGate {
  FakeGate(this.current);

  VaultGateState<VaultSession> current;
  int confirmed = 0;
  int retries = 0;
  final unlocks = <String>[];
  int passkeys = 0;
  String? unlockResult;
  String? passkeyResult;
  Completer<String?>? holdUnlock;

  @override
  VaultGateState<VaultSession> get state => current;

  @override
  Future<void> confirmSetup() async => confirmed += 1;

  @override
  Future<String?> unlock(String text) async {
    unlocks.add(text);
    if (holdUnlock != null) return holdUnlock!.future;
    return unlockResult;
  }

  @override
  Future<String?> unlockWithPasskey() async {
    passkeys += 1;
    return passkeyResult;
  }

  @override
  void retry() => retries += 1;
}

class FakeFiles implements FilesChannel {
  final shared = <(String, String, String)>[];

  @override
  Future<bool> shareFile(String name, Uint8List bytes, String mime) async {
    shared.add((name, utf8.decode(bytes), mime));
    return true;
  }

  @override
  Future<PickedFile?> pickFile({required List<String> mimeTypes, int maxBytes = 0}) async => null;

  @override
  Future<bool> saveFile(String name, Uint8List bytes, String mime) async => false;

  @override
  Future<void> clearShared() async {}
}

class FakeDeletion implements AccountDeletion {
  int deletes = 0;
  bool fails = false;

  @override
  Future<void> delete() async {
    deletes += 1;
    if (fails) throw StateError('offline');
  }
}

const key = 'ABCD-EFGH-JKMN-PQRS-TUVW-XYZ2-345';

void main() {
  late FakeFiles files;
  late FakeDeletion deletion;
  late FixedSession session;

  setUp(() {
    files = FakeFiles();
    deletion = FakeDeletion();
  });

  Future<FakeGate> pumpScreen(
    WidgetTester tester,
    VaultGateState<VaultSession> state, {
    bool passkeyOffered = false,
    List<int>? positions,
    Locale locale = const Locale('es'),
    int unsent = 0,
  }) async {
    final gate = FakeGate(state);
    session = FixedSession(signedIn('t'));
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultGateProvider.overrideWithValue(gate),
          vaultGateStateProvider.overrideWithValue(state),
          unlockPasskeyOfferedProvider.overrideWithValue(AsyncData(passkeyOffered)),
          filesChannelProvider.overrideWithValue(files),
          accountDeletionProvider.overrideWithValue(deletion),
          sessionProvider.overrideWith(() => session),
          unsentChangesProvider.overrideWithValue(() async => unsent),
        ],
        child: uiApp(
          locale: locale,
          width: 412,
          SizedBox(height: 915, child: VaultScreen(positions: positions)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return gate;
  }

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<PressButton>(button).onPressed != null;

  group('loading', () {
    for (final state in <VaultGateState<VaultSession>>[
      const Checking(),
      const Opening(),
      const Committing(),
    ]) {
      testWidgets('${state.status} shows the opening line and nothing to press', (tester) async {
        await pumpScreen(tester, state);
        expect(find.text('Abriendo tus datos…'), findsOneWidget);
        expect(find.byKey(const Key('vault.signOut')), findsNothing);
      });
    }
  });

  group('the recovery key', () {
    // Positions 1, 6, 12 and 26: group 1 char 1 (A), group 2 char 2 (F), group 3 char 4 (N),
    // group 7 char 2 (4).
    const positions = [1, 6, 12, 26];

    Future<FakeGate> toConfirm(WidgetTester tester) async {
      final gate = await pumpScreen(tester, const Setup(key), positions: positions);
      await tester.tap(find.byKey(const Key('vault.saved')));
      await tester.pumpAndSettle();
      return gate;
    }

    testWidgets('shows the key in groups, with Copy and Share and no download', (tester) async {
      await pumpScreen(tester, const Setup(key), positions: positions);
      expect(find.text('Guarda tu clave de recuperación'), findsOneWidget);
      for (final group in key.split('-')) {
        expect(find.text(group), findsOneWidget);
      }
      expect(find.byKey(const Key('vault.copy')), findsOneWidget);
      expect(find.byKey(const Key('vault.share')), findsOneWidget);
      expect(find.textContaining('Descargar'), findsNothing);
    });

    testWidgets('Copy puts the key on the clipboard and says so', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpScreen(tester, const Setup(key), positions: positions);
      await tester.tap(find.byKey(const Key('vault.copy')));
      await tester.pump();
      expect(copied, [key]);
      expect(find.text('COPIADA'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Share hands the key and one line about it to the share sheet', (tester) async {
      await pumpScreen(tester, const Setup(key), positions: positions);
      await tester.tap(find.byKey(const Key('vault.share')));
      await tester.pump();
      expect(files.shared, hasLength(1));
      final (name, text, mime) = files.shared.single;
      expect(name, 'wambito-recovery-key.txt');
      expect(mime, 'text/plain');
      expect(text, contains(key));
      expect(text, startsWith('Clave de recuperación de Wambito'));
      expect(text, contains('Guárdala en un lugar seguro'));
    });

    testWidgets('asks four characters at their positions, and Continue waits for them', (
      tester,
    ) async {
      final gate = await toConfirm(tester);
      expect(find.text('Confirma que la guardaste'), findsOneWidget);
      // Group g, character c: as the web's labels.
      expect(find.text('Grupo 1'), findsOneWidget);
      expect(find.text('carácter 1'), findsOneWidget);
      expect(find.text('Grupo 7'), findsOneWidget);
      final next = find.byKey(const Key('vault.continue'));
      expect(enabled(tester, next), isFalse);

      final boxes = find.byType(EditableText);
      expect(boxes, findsNWidgets(4));
      await tester.enterText(boxes.at(0), 'a');
      await tester.enterText(boxes.at(1), 'f');
      await tester.enterText(boxes.at(2), 'n');
      await tester.pump();
      expect(enabled(tester, next), isFalse);
      await tester.enterText(boxes.at(3), '4');
      await tester.pump();
      expect(enabled(tester, next), isTrue);

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(gate.confirmed, 1);
    });

    testWidgets('a wrong character says so and keeps Continue off', (tester) async {
      await toConfirm(tester);
      final boxes = find.byType(EditableText);
      for (final (i, c) in ['a', 'f', 'n', '9'].indexed) {
        await tester.enterText(boxes.at(i), c);
      }
      await tester.pump();
      expect(find.text('No coinciden. Revisa la clave que guardaste.'), findsOneWidget);
      expect(enabled(tester, find.byKey(const Key('vault.continue'))), isFalse);
    });

    testWidgets('"Ver la clave otra vez" goes back to the key', (tester) async {
      await toConfirm(tester);
      await tester.tap(find.byKey(const Key('vault.showAgain')));
      await tester.pumpAndSettle();
      expect(find.text('Guarda tu clave de recuperación'), findsOneWidget);
    });

    testWidgets('signing out is there, and signs out', (tester) async {
      await pumpScreen(tester, const Setup(key), positions: positions);
      await tester.tap(find.byKey(const Key('vault.signOut')));
      await tester.pumpAndSettle();
      expect(session.signOuts, ['t']);
    });
  });

  group('unlock', () {
    testWidgets('asks for the recovery key, and submit waits for text', (tester) async {
      await pumpScreen(tester, const Unlock());
      expect(find.text('Abre tus datos aquí'), findsOneWidget);
      final submit = find.byKey(const Key('vault.unlockSubmit'));
      expect(enabled(tester, submit), isFalse);
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), 'abcd');
      await tester.pump();
      expect(enabled(tester, submit), isTrue);
    });

    testWidgets('a wrong key says "That key does not open this account" and nothing more', (
      tester,
    ) async {
      final gate = await pumpScreen(tester, const Unlock());
      gate.unlockResult = 'wrong_recovery_key';
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), key);
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault.unlockSubmit')));
      await tester.pumpAndSettle();
      expect(gate.unlocks, [key]);
      expect(find.text('Esa clave no abre esta cuenta'), findsOneWidget);
      expect(find.textContaining('Prueba con la que guardaste'), findsNothing);
    });

    testWidgets('a key that does not parse says it is not in the right format', (tester) async {
      final gate = await pumpScreen(tester, const Unlock());
      gate.unlockResult = 'bad_recovery_key';
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), 'xx');
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault.unlockSubmit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Esa clave no tiene el formato correcto. Revisa que la copiaste completa.'),
        findsOneWidget,
      );
    });

    testWidgets('the button waits while the key is tried', (tester) async {
      final gate = await pumpScreen(tester, const Unlock());
      gate.holdUnlock = Completer<String?>();
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), key);
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault.unlockSubmit')));
      await tester.pump();
      expect(find.text('ABRIENDO…'), findsOneWidget);
      expect(enabled(tester, find.byKey(const Key('vault.unlockSubmit'))), isFalse);
      gate.holdUnlock!.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('ABRIENDO…'), findsNothing);
    });

    testWidgets('the passkey button shows only when passkeys can be used for this account', (
      tester,
    ) async {
      await pumpScreen(tester, const Unlock());
      expect(find.byKey(const Key('vault.passkey')), findsNothing);
      await pumpScreen(tester, const Unlock(), passkeyOffered: true);
      expect(find.byKey(const Key('vault.passkey')), findsOneWidget);
    });

    testWidgets('the passkey button asks the gate, and shows its error under it', (tester) async {
      final gate = await pumpScreen(tester, const Unlock(), passkeyOffered: true);
      gate.passkeyResult = 'no_passkey_wrap';
      await tester.tap(find.byKey(const Key('vault.passkey')));
      await tester.pumpAndSettle();
      expect(gate.passkeys, 1);
      expect(find.textContaining('Esta llave de acceso todavía no abre tus datos'), findsOneWidget);
    });

    testWidgets('says why the phone was asked again', (tester) async {
      await pumpScreen(tester, const Unlock(notice: Unlock.removed));
      expect(find.textContaining('Este teléfono se eliminó de tu cuenta'), findsOneWidget);
      await pumpScreen(tester, const Unlock(notice: Unlock.unverified));
      expect(find.textContaining('Este teléfono no pudo verificar la clave nueva'), findsOneWidget);
    });
  });

  group('locked', () {
    testWidgets('offline says so and retries', (tester) async {
      final gate = await pumpScreen(tester, const Locked(LockedKind.offline, false));
      expect(find.text('Sin conexión'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault.retry')));
      await tester.pump();
      expect(gate.retries, 1);
    });

    testWidgets('while it retries the button says so and waits', (tester) async {
      await pumpScreen(tester, const Locked(LockedKind.error, true));
      expect(find.text('No pudimos abrir tus datos'), findsOneWidget);
      expect(find.text('REINTENTANDO…'), findsOneWidget);
      expect(enabled(tester, find.byKey(const Key('vault.retry'))), isFalse);
    });

    testWidgets('unsupported has no retry, only the way out', (tester) async {
      await pumpScreen(tester, const Locked(LockedKind.unsupported, false));
      expect(find.byKey(const Key('vault.retry')), findsNothing);
      expect(find.byKey(const Key('vault.signOut')), findsOneWidget);
    });

    testWidgets('a guest can delete the account in two taps', (tester) async {
      await pumpScreen(tester, const Locked(LockedKind.guest, false));
      expect(find.text('Tus datos no se pueden abrir aquí'), findsOneWidget);
      expect(find.byKey(const Key('vault.retry')), findsNothing);
      await tester.tap(find.byKey(const Key('vault.deleteAccount')));
      await tester.pumpAndSettle();
      expect(deletion.deletes, 0);
      await tester.tap(find.byKey(const Key('vault.deleteConfirm')));
      await tester.pumpAndSettle();
      expect(deletion.deletes, 1);
    });

    testWidgets('a delete that fails says so and can be tried again', (tester) async {
      deletion.fails = true;
      await pumpScreen(tester, const Locked(LockedKind.guest, false));
      await tester.tap(find.byKey(const Key('vault.deleteAccount')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault.deleteConfirm')));
      await tester.pumpAndSettle();
      expect(find.text('No pudimos eliminarla. Inténtalo de nuevo.'), findsOneWidget);
    });

    for (final state in <VaultGateState<VaultSession>>[
      const Unlock(notice: 'unverified'),
      const Locked(LockedKind.error, false),
    ]) {
      testWidgets('${state.runtimeType}: changes the kept vault never sent are asked about first '
          '(no sync: the vault is not open)', (tester) async {
        await pumpScreen(tester, state, unsent: 2);
        await tester.tap(find.byKey(const Key('vault.signOut')));
        await tester.pumpAndSettle();
        expect(find.text('Tienes 2 cambios sin sincronizar'), findsOneWidget);
        expect(find.byKey(const Key('vault.syncAndSignOut')), findsNothing);
        await tester.tap(find.text('CANCELAR'));
        await tester.pumpAndSettle();
        expect(session.signOuts, isEmpty);
        await tester.tap(find.byKey(const Key('vault.signOut')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('vault.signOutAnyway')));
        await tester.pumpAndSettle();
        expect(session.signOuts, ['t']);
      });
    }

    testWidgets('signing out signs out', (tester) async {
      await pumpScreen(tester, const Locked(LockedKind.error, false));
      await tester.tap(find.byKey(const Key('vault.signOut')));
      await tester.pumpAndSettle();
      expect(session.signOuts, ['t']);
    });
  });
}
