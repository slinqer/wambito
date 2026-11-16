// The screen lock before a sensitive operation (spec section 7.7, D15/D18): the phone's own lock when
// it has one, else the current recovery key.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:wambito/local/keys_error.dart';
import 'package:wambito/security/screen_lock.dart';
import 'package:wambito/ui/press_button.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';

class _FakeLock implements ScreenLock {
  _FakeLock(this.answer);

  final LockCheck answer;
  final reasons = <String>[];

  @override
  Future<LockCheck> confirm(String reason) async {
    reasons.add(reason);
    return answer;
  }
}

class _Ask extends ConsumerWidget {
  const _Ask({required this.check, required this.result});

  final Future<void> Function(String text) check;
  final List<bool> result;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PressButton.text(
    'Ask',
    onPressed: () async {
      result.add(
        await confirmSensitive(context, ref, reason: 'Remove this device', checkRecoveryKey: check),
      );
    },
  );
}

Future<(_FakeLock, List<bool>, List<String>)> _open(
  WidgetTester t,
  LockCheck answer, {
  Future<void> Function(String text)? check,
}) async {
  t.view
    ..physicalSize = const Size(824, 1830)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final lock = _FakeLock(answer);
  final result = <bool>[];
  final tried = <String>[];
  await t.pumpWidget(
    ProviderScope(
      overrides: [screenLockProvider.overrideWithValue(lock)],
      child: uiApp(
        _Ask(
          result: result,
          check:
              check ??
              (text) async {
                tried.add(text);
              },
        ),
        locale: const Locale('en'),
      ),
    ),
  );
  await t.tap(find.text('ASK'));
  await t.pumpAndSettle();
  return (lock, result, tried);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('passed returns true and shows no sheet', (t) async {
    final (lock, result, _) = await _open(t, LockCheck.passed);
    expect(result, [true]);
    expect(lock.reasons, ['Remove this device']);
    expect(find.byKey(const Key('screenLock.key')), findsNothing);
  });

  testWidgets('cancelled returns false and shows no sheet', (t) async {
    final (_, result, _) = await _open(t, LockCheck.cancelled);
    expect(result, [false]);
    expect(find.byKey(const Key('screenLock.key')), findsNothing);
  });

  testWidgets('no lock asks the recovery key, and the right one returns true', (t) async {
    final (_, result, tried) = await _open(t, LockCheck.noLock);
    expect(result, isEmpty);
    expect(find.byKey(const Key('screenLock.key')), findsOneWidget);
    await t.enterText(find.byKey(const Key('screenLock.key')), 'ABCD-EFGH');
    await t.pump();
    await t.tap(find.byKey(const Key('screenLock.submit')));
    await t.pumpAndSettle();
    expect(tried, ['ABCD-EFGH']);
    expect(result, [true]);
    expect(find.byKey(const Key('screenLock.key')), findsNothing);
  });

  testWidgets('no lock: a wrong key says so and the sheet stays', (t) async {
    final (_, result, _) = await _open(
      t,
      LockCheck.noLock,
      check: (_) async => throw const KeysError('wrong_recovery_key'),
    );
    await t.enterText(find.byKey(const Key('screenLock.key')), 'ABCD-EFGH');
    await t.pump();
    await t.tap(find.byKey(const Key('screenLock.submit')));
    await t.pumpAndSettle();
    expect(find.text('That key does not open this account'), findsOneWidget);
    expect(find.byKey(const Key('screenLock.key')), findsOneWidget);
    expect(result, isEmpty);
  });

  testWidgets('no lock: a key in the wrong format says so', (t) async {
    await _open(t, LockCheck.noLock, check: (_) async => throw const KeysError('bad_recovery_key'));
    await t.enterText(find.byKey(const Key('screenLock.key')), 'x');
    await t.pump();
    await t.tap(find.byKey(const Key('screenLock.submit')));
    await t.pumpAndSettle();
    expect(find.textContaining('not in the right format'), findsOneWidget);
  });

  testWidgets('no lock: the key field does not feed keyboard learning', (t) async {
    await _open(t, LockCheck.noLock);
    final editable = t.widget<EditableText>(find.byType(EditableText));
    expect(editable.enableIMEPersonalizedLearning, isFalse);
  });

  testWidgets('no lock: closing the sheet returns false', (t) async {
    final (_, result, _) = await _open(t, LockCheck.noLock);
    await t.tap(find.text('CANCEL'));
    await t.pumpAndSettle();
    expect(result, [false]);
  });

  group('LocalAuthScreenLock', () {
    LocalAuthScreenLock lock({
      bool supported = true,
      bool answer = false,
      LocalAuthExceptionCode? error,
      List<String>? asked,
    }) => LocalAuthScreenLock(
      isSupported: () async => supported,
      authenticate: (reason) async {
        asked?.add(reason);
        if (error != null) throw LocalAuthException(code: error);
        return answer;
      },
    );

    test('passes when the phone says it did, asking with the reason', () async {
      final asked = <String>[];
      expect(await lock(answer: true, asked: asked).confirm('why'), LockCheck.passed);
      expect(asked, ['why']);
    });

    test('a phone without a lock is noLock, and is not asked', () async {
      final asked = <String>[];
      expect(await lock(supported: false, asked: asked).confirm('why'), LockCheck.noLock);
      expect(asked, isEmpty);
    });

    test('noCredentialsSet is noLock', () async {
      expect(
        await lock(error: LocalAuthExceptionCode.noCredentialsSet).confirm('why'),
        LockCheck.noLock,
      );
    });

    test('any other error is cancelled, never thrown', () async {
      final broken = LocalAuthScreenLock(
        isSupported: () async => throw PlatformException(code: 'boom'),
        authenticate: (_) async => true,
      );
      expect(await broken.confirm('why'), LockCheck.cancelled);
    });

    test('a refusal or a cancel is cancelled', () async {
      expect(await lock().confirm('why'), LockCheck.cancelled);
      for (final code in [
        LocalAuthExceptionCode.userCanceled,
        LocalAuthExceptionCode.systemCanceled,
        LocalAuthExceptionCode.timeout,
        LocalAuthExceptionCode.temporaryLockout,
        LocalAuthExceptionCode.biometricLockout,
        LocalAuthExceptionCode.uiUnavailable,
        LocalAuthExceptionCode.unknownError,
      ]) {
        expect(await lock(error: code).confirm('why'), LockCheck.cancelled, reason: '$code');
      }
    });
  });
}
