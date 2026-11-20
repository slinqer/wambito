import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/merge/merge_controller.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/files/files_channel.dart';
import 'package:wambito/local/keys.dart' show LocalKeys;
import 'package:wambito/local/pairing.dart' show PairingError;
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/vault/pair_new_device_view.dart' show PairingQr;
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

  int pairs = 0;
  int leaves = 0;
  final started = <FakePairing>[];
  Future<GatePairing<LocalKeys>> Function()? onStart;

  @override
  Future<void> pair() async => pairs += 1;

  @override
  Future<GatePairing<LocalKeys>> startPairing() async {
    if (onStart != null) return onStart!();
    final next = FakePairing('p-${started.length + 1}');
    started.add(next);
    return next;
  }

  @override
  void leavePairing() => leaves += 1;
}

/// A new-device request the test settles: its number, its end.
class FakePairing implements GatePairing<LocalKeys> {
  FakePairing(this.id);

  @override
  final String id;
  final numbered = Completer<String>();
  final finished = Completer<LocalKeys>();
  int cancels = 0;

  @override
  String get code => 'AB3DEFGH';
  @override
  String get qr => 'wambito://pair?id=$id&key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';
  @override
  String get expiresAt => '2026-11-10T14:10:00Z';
  @override
  Future<String> number() => numbered.future;
  @override
  Future<LocalKeys> finish() => finished.future;
  @override
  void cancel() => cancels += 1;
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

const key = 'ABCD-EFGH-JKMN-PQRS-TUVW-XYZ2-345';

/// A full key in the key's alphabet (no U), as the unlock field keeps it.
const typedKey = 'ABCD-EFGH-JKMN-PQRS-TVWX-YZ23-456';

void main() {
  late FakeFiles files;
  late FixedSession session;

  setUp(() {
    files = FakeFiles();
  });

  Future<FakeGate> pumpScreen(
    WidgetTester tester,
    VaultGateState<VaultSession> state, {
    bool passkeyOffered = false,
    List<int>? positions,
    Locale locale = const Locale('es'),
    int unsent = 0,
    void Function(FakeGate gate)? prepare,
    List<Override> extra = const [],
    Future<bool>? offered,
  }) async {
    final gate = FakeGate(state);
    prepare?.call(gate);
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
          if (offered != null)
            unlockPasskeyOfferedProvider.overrideWith((ref) => offered)
          else
            unlockPasskeyOfferedProvider.overrideWithValue(AsyncData(passkeyOffered)),
          filesChannelProvider.overrideWithValue(files),
          sessionProvider.overrideWith(() => session),
          unsentChangesProvider.overrideWithValue(() async => unsent),
          pairingTimeZoneProvider.overrideWithValue('America/Bogota'),
          ...extra,
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
    testWidgets('while a merge waits, Unlock says why and signing out calls the merge off', (
      tester,
    ) async {
      final merge = _WaitingMerge();
      await pumpScreen(
        tester,
        const Unlock(),
        extra: [mergeControllerProvider.overrideWith(() => merge)],
      );
      expect(find.byKey(const Key('unlock.mergeWaiting')), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault.signOut')));
      await tester.pumpAndSettle();
      expect(merge.cancels, 1);
      expect(session.signOuts, isEmpty);
    });

    testWidgets('without a merge, Unlock has no merge line', (tester) async {
      await pumpScreen(tester, const Unlock());
      expect(find.byKey(const Key('unlock.mergeWaiting')), findsNothing);
    });

    // The recovery key leads when this phone's last passkey touch gave no PRF.
    const keyFirst = Unlock<VaultSession>(noPrfHere: true);

    Future<void> openMore(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('vault.more')));
      await tester.tap(find.byKey(const Key('vault.more')));
      await tester.pumpAndSettle();
    }

    String fieldText(WidgetTester tester) =>
        tester.widget<EditableText>(find.byKey(const Key('vault.recoveryKey'))).controller.text;

    bool fieldFocused(WidgetTester tester) =>
        tester.widget<EditableText>(find.byKey(const Key('vault.recoveryKey'))).focusNode.hasFocus;

    /// The top of [finder] on screen, to check the order of the actions.
    double top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

    testWidgets('key first shows the field and the line', (tester) async {
      await pumpScreen(tester, keyFirst, passkeyOffered: true);
      expect(find.byKey(const Key('vault.recoveryKey')), findsOneWidget);
      expect(
        find.text(
          'Tu huella te deja entrar, pero tu gestor de contraseñas no le permite abrir tus datos.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Escribe tu clave de recuperación para abrirlos'), findsOneWidget);
      // Pairing below the key, another passkey under "More options", closed.
      expect(find.byKey(const Key('vault.pair')), findsOneWidget);
      expect(
        top(tester, find.byKey(const Key('vault.pair'))),
        greaterThan(top(tester, find.byKey(const Key('vault.unlockSubmit')))),
      );
      expect(find.byKey(const Key('vault.passkey')), findsNothing);
      await openMore(tester);
      expect(find.text('USAR OTRA HUELLA'), findsOneWidget);
      expect(
        top(tester, find.byKey(const Key('vault.signOut'))),
        greaterThan(top(tester, find.byKey(const Key('vault.passkey')))),
      );
    });

    testWidgets('key first without a passkey wrap has nothing under More options', (tester) async {
      await pumpScreen(
        tester,
        const Unlock(noPrfHere: true, passkeyWrap: false),
        passkeyOffered: true,
      );
      expect(find.byKey(const Key('vault.recoveryKey')), findsOneWidget);
      expect(find.byKey(const Key('vault.more')), findsNothing);
      expect(find.byKey(const Key('vault.passkey')), findsNothing);
    });

    testWidgets('passkey first hides the field until More options', (tester) async {
      final handle = tester.ensureSemantics();
      final gate = await pumpScreen(tester, const Unlock(), passkeyOffered: true);
      expect(find.text('ABRIR CON MI HUELLA'), findsOneWidget);
      expect(find.textContaining('Elige cómo abrirlos en este teléfono'), findsOneWidget);
      expect(find.textContaining('tu gestor de contraseñas no le permite'), findsNothing);
      expect(find.byKey(const Key('vault.recoveryKey')), findsNothing);
      expect(
        top(tester, find.byKey(const Key('vault.pair'))),
        greaterThan(top(tester, find.byKey(const Key('vault.passkey')))),
      );
      // No passkey prompt without a tap.
      expect(gate.passkeys, 0);
      expect(find.text('MÁS OPCIONES'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('vault.more'))),
        matchesSemantics(
          label: 'MÁS OPCIONES',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await openMore(tester);
      expect(find.byKey(const Key('vault.recoveryKey')), findsOneWidget);
      // Opened by hand: the field takes the focus.
      expect(fieldFocused(tester), isTrue);
      await tester.tap(find.byKey(const Key('vault.passkey')));
      await tester.pumpAndSettle();
      expect(gate.passkeys, 1);
      handle.dispose();
    });

    /// The primary button on screen: its key, and whether it can be tapped.
    (Key?, bool) primary(WidgetTester tester) {
      final buttons = tester
          .widgetList<PressButton>(find.byType(PressButton))
          .where((b) => b.tone == PressTone.primary)
          .toList();
      expect(buttons, hasLength(1));
      return (buttons.single.key, buttons.single.onPressed != null);
    }

    testWidgets('while it is not known whether passkeys work here, the layout holds: the passkey '
        'leads, waiting, and nothing below it moves into its place', (tester) async {
      final known = Completer<bool>();
      await pumpScreen(tester, const Unlock(), offered: known.future);
      expect(primary(tester), (const Key('vault.passkey'), false));
      // Pairing waits too: its place is not settled yet.
      expect(enabled(tester, find.byKey(const Key('vault.pair'))), isFalse);
      expect(find.byKey(const Key('vault.recoveryKey')), findsNothing);
      known.complete(true);
      await tester.pumpAndSettle();
      // Once tappable, the same button in the same place.
      expect(primary(tester), (const Key('vault.passkey'), true));
      expect(enabled(tester, find.byKey(const Key('vault.pair'))), isTrue);
    });

    testWidgets('no passkeys after all: pairing leads, and it was never tappable before', (
      tester,
    ) async {
      final known = Completer<bool>();
      await pumpScreen(tester, const Unlock(error: 'wrong_recovery_key'), offered: known.future);
      expect(primary(tester), (const Key('vault.passkey'), false));
      // The sign-in key's error: the field is in sight from the start, and stays.
      expect(find.byKey(const Key('vault.recoveryKey')), findsOneWidget);
      known.complete(false);
      await tester.pumpAndSettle();
      expect(primary(tester), (const Key('vault.pair'), true));
      expect(find.byKey(const Key('vault.passkey')), findsNothing);
      expect(find.byKey(const Key('vault.recoveryKey')), findsOneWidget);
    });

    testWidgets('without a passkey wrap the loading changes nothing: pairing leads at once', (
      tester,
    ) async {
      await pumpScreen(tester, const Unlock(passkeyWrap: false), offered: Completer<bool>().future);
      expect(primary(tester), (const Key('vault.pair'), true));
    });

    testWidgets('the Paste button is a button named Pegar', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, keyFirst);
      expect(
        tester.getSemantics(find.byKey(const Key('vault.paste'))),
        matchesSemantics(
          label: 'PEGAR',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('the key field asks for a keyboard that composes nothing', (tester) async {
      await pumpScreen(tester, keyFirst);
      final field = tester.widget<EditableText>(find.byKey(const Key('vault.recoveryKey')));
      expect(field.keyboardType, TextInputType.visiblePassword);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.textCapitalization, TextCapitalization.characters);
    });

    testWidgets('pair first', (tester) async {
      final gate = await pumpScreen(tester, const Unlock(passkeyWrap: false), passkeyOffered: true);
      expect(find.byKey(const Key('vault.passkey')), findsNothing);
      expect(find.byKey(const Key('vault.recoveryKey')), findsNothing);
      expect(find.text('AÑADIR ESTE TELÉFONO DESDE OTRO DISPOSITIVO'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault.pair')));
      await tester.pump();
      expect(gate.pairs, 1);
      await openMore(tester);
      expect(find.byKey(const Key('vault.recoveryKey')), findsOneWidget);
      // Without passkeys on the phone, a passkey wrap changes nothing: pairing leads.
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester, const Unlock());
      expect(find.byKey(const Key('vault.passkey')), findsNothing);
      expect(find.byKey(const Key('vault.recoveryKey')), findsNothing);
      expect(find.byKey(const Key('vault.more')), findsOneWidget);
    });

    for (final code in ['no_prf', 'no_passkey_wrap']) {
      testWidgets('a failed passkey touch opens More options ($code)', (tester) async {
        final gate = await pumpScreen(tester, const Unlock(), passkeyOffered: true);
        gate.passkeyResult = code;
        await tester.tap(find.byKey(const Key('vault.passkey')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('vault.recoveryKey')), findsOneWidget);
        // Opened by itself: the error is said, the field does not take the focus.
        expect(fieldFocused(tester), isFalse);
        expect(
          find.textContaining(
            code == 'no_prf'
                ? 'Esta huella no puede abrir tus datos'
                : 'Esta huella todavía no abre tus datos',
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('a cancelled or other passkey failure leaves More options closed', (tester) async {
      final gate = await pumpScreen(tester, const Unlock(), passkeyOffered: true);
      await tester.tap(find.byKey(const Key('vault.passkey')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault.recoveryKey')), findsNothing);
      gate.passkeyResult = 'offline';
      await tester.tap(find.byKey(const Key('vault.passkey')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault.recoveryKey')), findsNothing);
      expect(find.textContaining('No hay conexión'), findsOneWidget);
    });

    testWidgets('Paste fills and groups the field', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': ' abcd efgh\njkmn-pqrs tvwx yz23 456 '};
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final gate = await pumpScreen(tester, keyFirst);
      expect(find.text('PEGAR'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault.paste')));
      await tester.pumpAndSettle();
      expect(fieldText(tester), typedKey);
      expect(enabled(tester, find.byKey(const Key('vault.unlockSubmit'))), isTrue);
      await tester.tap(find.byKey(const Key('vault.unlockSubmit')));
      await tester.pumpAndSettle();
      expect(gate.unlocks, [typedKey]);
    });

    testWidgets('typing groups the key, and submit waits for a full key', (tester) async {
      await pumpScreen(tester, keyFirst);
      expect(find.text('Abre tus datos aquí'), findsOneWidget);
      final submit = find.byKey(const Key('vault.unlockSubmit'));
      expect(enabled(tester, submit), isFalse);
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), 'abcdefgh');
      await tester.pump();
      expect(fieldText(tester), 'ABCD-EFGH');
      expect(enabled(tester, submit), isFalse);
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), typedKey.toLowerCase());
      await tester.pump();
      expect(enabled(tester, submit), isTrue);
    });

    testWidgets('a wrong key says "That key does not open this account" and nothing more', (
      tester,
    ) async {
      final gate = await pumpScreen(tester, keyFirst);
      gate.unlockResult = 'wrong_recovery_key';
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), typedKey);
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault.unlockSubmit')));
      await tester.pumpAndSettle();
      expect(gate.unlocks, [typedKey]);
      expect(find.text('Esa clave no abre esta cuenta'), findsOneWidget);
      expect(find.textContaining('Prueba con la que guardaste'), findsNothing);
    });

    testWidgets('a key that does not parse says it is not in the right format', (tester) async {
      final gate = await pumpScreen(tester, keyFirst);
      gate.unlockResult = 'bad_recovery_key';
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), typedKey);
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault.unlockSubmit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Esa clave no tiene el formato correcto. Revisa que la copiaste completa.'),
        findsOneWidget,
      );
    });

    testWidgets("the sign-in key's error opens More options on the field", (tester) async {
      await pumpScreen(tester, const Unlock(error: 'wrong_recovery_key'), passkeyOffered: true);
      expect(find.byKey(const Key('vault.recoveryKey')), findsOneWidget);
      expect(find.text('Esa clave no abre esta cuenta'), findsOneWidget);
    });

    testWidgets('the button waits while the key is tried', (tester) async {
      final gate = await pumpScreen(tester, keyFirst);
      gate.holdUnlock = Completer<String?>();
      await tester.enterText(find.byKey(const Key('vault.recoveryKey')), typedKey);
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
      expect(find.textContaining('Esta huella todavía no abre tus datos'), findsOneWidget);
      expect(find.textContaining('llave'), findsNothing);
    });

    testWidgets('in English the passkey leads with "Open with my fingerprint"', (tester) async {
      await pumpScreen(tester, const Unlock(), passkeyOffered: true, locale: const Locale('en'));
      expect(find.text('OPEN WITH MY FINGERPRINT'), findsOneWidget);
      expect(find.text('MORE OPTIONS'), findsOneWidget);
    });

    testWidgets('says why the phone was asked again', (tester) async {
      await pumpScreen(tester, const Unlock(notice: Unlock.removed));
      expect(find.textContaining('Este teléfono se eliminó de tu cuenta'), findsOneWidget);
      await pumpScreen(tester, const Unlock(notice: Unlock.unverified));
      expect(find.textContaining('Este teléfono no pudo verificar la clave nueva'), findsOneWidget);
      expect(find.textContaining('usa tu huella'), findsOneWidget);
    });
  });

  group('pairing', () {
    testWidgets('Unlock offers "Añadir este teléfono desde otro dispositivo" and asks the gate', (
      tester,
    ) async {
      final gate = await pumpScreen(tester, const Unlock());
      expect(find.text('AÑADIR ESTE TELÉFONO DESDE OTRO DISPOSITIVO'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault.pair')));
      await tester.pump();
      expect(gate.pairs, 1);
    });

    testWidgets('in English it reads "Add this phone from another device"', (tester) async {
      await pumpScreen(tester, const Unlock(), locale: const Locale('en'));
      expect(find.text('ADD THIS PHONE FROM ANOTHER DEVICE'), findsOneWidget);
    });

    for (final kind in LockedKind.values) {
      testWidgets('Locked ($kind) offers neither pairing nor deleting the account: pairing starts '
          'from Unlock', (tester) async {
        await pumpScreen(tester, Locked(kind, false));
        expect(find.byKey(const Key('vault.pair')), findsNothing);
        expect(find.byKey(const Key('vault.deleteAccount')), findsNothing);
        expect(find.byKey(const Key('vault.signOut')), findsOneWidget);
      });
    }

    testWidgets('shows the QR, the 8-character code under it and when it expires', (tester) async {
      final gate = await pumpScreen(tester, const Pairing(PairingFrom.unlock));
      expect(find.text('Abre tus datos desde otro dispositivo'), findsOneWidget);
      final qr = tester.widget<PairingQr>(find.byType(PairingQr));
      expect(qr.data, gate.started.single.qr);
      expect(find.text('AB3D EFGH'), findsOneWidget);
      // 14:10 UTC is 09:10 in Bogota
      expect(find.textContaining('09:10'), findsOneWidget);
      expect(find.text('Esperando a tu otro dispositivo…'), findsOneWidget);
    });

    testWidgets('the number appears once known, and the code goes', (tester) async {
      final gate = await pumpScreen(tester, const Pairing(PairingFrom.unlock));
      gate.started.single.numbered.complete('042917');
      await tester.pumpAndSettle();
      expect(find.text('042 917'), findsOneWidget);
      expect(find.text('Comprueba que las dos pantallas muestran el mismo número'), findsOneWidget);
      expect(find.byType(PairingQr), findsNothing);
      expect(find.text('AB3D EFGH'), findsNothing);
    });

    testWidgets('Back asks the gate to leave, and leaving cancels the request', (tester) async {
      final gate = await pumpScreen(tester, const Pairing(PairingFrom.unlock));
      await tester.tap(find.byKey(const Key('vault.pairBack')));
      await tester.pump();
      expect(gate.leaves, 1);
      // the gate moves on: the screen goes with the request
      await tester.pumpWidget(const SizedBox());
      expect(gate.started.single.cancels, 1);
    });

    testWidgets('an expired code says so and starts again with a new request', (tester) async {
      final gate = await pumpScreen(tester, const Pairing(PairingFrom.unlock));
      gate.started.single.numbered.completeError(const PairingError('expired'));
      await tester.pumpAndSettle();
      expect(find.text('Este código caducó'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault.pairRestart')));
      await tester.pumpAndSettle();
      expect(gate.started, hasLength(2));
      expect(find.byType(PairingQr), findsOneWidget);
    });

    testWidgets('a tampered pairing stops with a warning and no restart', (tester) async {
      final gate = await pumpScreen(tester, const Pairing(PairingFrom.unlock));
      gate.started.single.finished.completeError(const PairingError('tampered'));
      await tester.pumpAndSettle();
      expect(
        find.text('Detente: puede que alguien esté interfiriendo. No se compartió nada.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vault.pairRestart')), findsNothing);
      expect(find.byKey(const Key('vault.pairBack')), findsOneWidget);
    });

    testWidgets('a cancelled request shows nothing', (tester) async {
      final gate = await pumpScreen(tester, const Pairing(PairingFrom.unlock));
      gate.started.single.numbered.completeError(const PairingError('cancelled'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo terminar'), findsNothing);
      expect(find.byType(PairingQr), findsOneWidget);
    });

    testWidgets('a request that cannot start says why', (tester) async {
      await pumpScreen(
        tester,
        const Pairing(PairingFrom.unlock),
        prepare: (g) => g.onStart = () async => throw const PairingError('offline'),
      );
      expect(
        find.text('No hay conexión. Empieza de nuevo cuando vuelvas a tenerla.'),
        findsOneWidget,
      );
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

class _WaitingMerge extends MergeController {
  var cancels = 0;

  @override
  MergeState build() => const MergeWaitingUnlock();

  @override
  Future<void> cancel() async => cancels += 1;
}
