@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/entry/email_screen.dart';
import 'package:wambito/entry/verify_link_screen.dart';
import 'package:wambito/ui/app_shell.dart';

import '../entry/fakes.dart';
import '../support/parity.dart';
import '../support/parity_home.dart' show precacheWambi;

/// The entry screens against the stories that show them: `sign-in-signin--*` and
/// `sign-in-verify--*` (apps/web/app/features/sign-in/SignIn.stories.tsx and Verify.stories.tsx),
/// each as Storybook shows it after its `play` function, in night and in day (`PasskeyFailed` and
/// `ExpiredDay` pin day, and English).
///
/// Storybook pads every story by 16px, so the screens sit in a [ShellFrame] with that padding (and
/// no 🎤, which only the bar has). The app focuses the email field on opening (the person came by
/// tapping "Ya tengo una cuenta", and the keyboard is what they want), where the web leaves it
/// alone so the keyboard does not cover Wambi; the pairs put the focus down again, as the web has
/// it. The code step's "Reenviar código" waits 30 s as the web's does, counted by the app's clock,
/// which [parityGolden] pins to the story's (so both sides read "Reenviar en 30 s"). The passkey
/// button reads the web's words, "Entrar con huella" (in English through `EmailScreen.passkeyLabel`).
///
/// Update the goldens with `flutter test --update-goldens test/parity`, then compare with
/// `dart run tool/parity/compose.dart` (docs/mobile/parity.md).

Widget _frame(Widget screen) =>
    ShellFrame(padding: const EdgeInsets.all(16), showMic: false, child: screen);

List<Override> _overrides(FakeAuthApi auth, {bool passkeys = false}) => [
  authApiProvider.overrideWithValue(auth),
  passkeysProvider.overrideWithValue(FakePasskeys(isSupported: passkeys)),
];

/// An auth server whose code check never answers (`CheckingCode`).
class _HangingAuth extends FakeAuthApi {
  @override
  Future<String> verifyCode(String email, String code) {
    calls.add('verifyCode $email $code');
    return Completer<String>().future;
  }
}

Finder _field(String key) => find.byKey(Key(key));

/// The focus the web's email step opens without.
Future<void> _putFocusDown(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
}

Future<void> _sendCodeTo(WidgetTester t, String email) async {
  await t.enterText(_field('entry.email'), email);
  await t.tap(_field('entry.send'));
  await t.pumpAndSettle();
}

/// Types [code] a digit at a time, as the story's keyboard does.
Future<void> _typeCode(WidgetTester t, String code) async {
  for (var i = 1; i <= code.length; i++) {
    await t.enterText(_field('entry.code'), code.substring(0, i));
  }
  await t.pump();
}

/// Types the code, lets "Entrar" see it whole, and taps it.
Future<void> _submitCode(WidgetTester t, String code) async {
  await _typeCode(t, code);
  await t.tap(_field('entry.submitCode'));
}

/// The story's `userEvent.click` left the focus on the control it clicked, which Chrome rings:
/// the control takes it, and a key puts the app in keyboard mode, where it shows.
Future<void> _focusRinged(WidgetTester t, String key) async {
  final focus = t.widget<Focus>(
    find.descendant(of: _field(key), matching: find.byType(Focus)).first,
  );
  focus.focusNode!.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.shift);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final theme in ['night', 'day']) {
    testWidgets('entry parity: the email step ($theme)', (t) async {
      await parityGolden(
        t,
        'signin-email-step',
        _frame(const EmailScreen()),
        theme: theme,
        overrides: _overrides(FakeAuthApi()),
        act: (t) async {
          await precacheWambi(t);
          await _putFocusDown(t);
        },
      );
    });

    testWidgets('entry parity: a mistyped email ($theme)', (t) async {
      await parityGolden(
        t,
        'signin-invalid-email',
        _frame(const EmailScreen()),
        theme: theme,
        overrides: _overrides(FakeAuthApi()),
        act: (t) async {
          await precacheWambi(t);
          await _sendCodeTo(t, 'ana@');
        },
      );
    });

    testWidgets('entry parity: too many codes asked for ($theme)', (t) async {
      final auth = FakeAuthApi()..failures['sendCode'] = const AuthFailure(status: 429);
      await parityGolden(
        t,
        'signin-too-many-codes',
        _frame(const EmailScreen()),
        theme: theme,
        overrides: _overrides(auth),
        act: (t) async {
          await precacheWambi(t);
          await _sendCodeTo(t, 'ana@example.com');
        },
      );
    });

    testWidgets('entry parity: the code step ($theme)', (t) async {
      await parityGolden(
        t,
        'signin-code-step',
        _frame(const EmailScreen()),
        theme: theme,
        overrides: _overrides(FakeAuthApi()),
        act: (t) async {
          await precacheWambi(t);
          await _sendCodeTo(t, 'ana@example.com');
        },
      );
    });

    testWidgets('entry parity: a wrong code ($theme)', (t) async {
      final auth = FakeAuthApi();
      await parityGolden(
        t,
        'signin-wrong-code',
        _frame(const EmailScreen()),
        theme: theme,
        overrides: _overrides(auth),
        act: (t) async {
          await precacheWambi(t);
          await _sendCodeTo(t, 'ana@example.com');
          auth.failures['verifyCode'] = const AuthFailure(code: 'INVALID_OTP', status: 400);
          await _submitCode(t, '123456');
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('entry parity: the code being checked ($theme)', (t) async {
      await parityGolden(
        t,
        'signin-checking-code',
        _frame(const EmailScreen()),
        theme: theme,
        overrides: _overrides(_HangingAuth()),
        act: (t) async {
          await precacheWambi(t);
          await _sendCodeTo(t, 'ana@example.com');
          await _submitCode(t, '123456');
          await t.pump();
        },
      );
    });

    testWidgets('entry parity: no connection keeps the code ($theme)', (t) async {
      final auth = FakeAuthApi();
      await parityGolden(
        t,
        'signin-offline-keeps-code',
        _frame(const EmailScreen()),
        theme: theme,
        overrides: _overrides(auth),
        act: (t) async {
          await precacheWambi(t);
          await _sendCodeTo(t, 'ana@example.com');
          auth.failures['verifyCode'] = const AuthFailure(status: 0);
          await _submitCode(t, '123456');
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('entry parity: the passkey button, after a passkey ($theme)', (t) async {
      await parityGolden(
        t,
        'signin-fingerprint-button',
        _frame(const EmailScreen(passkeyLabel: 'Entrar con huella')),
        theme: theme,
        overrides: _overrides(FakeAuthApi(), passkeys: true),
        act: (t) async {
          await precacheWambi(t);
          await _putFocusDown(t);
        },
      );
    });

    testWidgets('entry parity: the magic link being checked ($theme)', (t) async {
      await parityGolden(
        t,
        'verify-checking',
        _frame(const VerifyLinkScreen(email: 'ana@example.com', code: '424242')),
        theme: theme,
        overrides: _overrides(_HangingAuth()),
        act: precacheWambi,
      );
    });

    testWidgets('entry parity: a magic link that was rejected ($theme)', (t) async {
      final auth = FakeAuthApi()
        ..failures['verifyCode'] = const AuthFailure(code: 'OTP_EXPIRED', status: 400);
      await parityGolden(
        t,
        'verify-rejected',
        _frame(const VerifyLinkScreen(email: 'ana@example.com', code: '424242')),
        theme: theme,
        overrides: _overrides(auth),
        act: precacheWambi,
      );
    });

    testWidgets('entry parity: a magic link with no connection ($theme)', (t) async {
      final auth = FakeAuthApi()..failures['verifyCode'] = const AuthFailure(status: 0);
      await parityGolden(
        t,
        'verify-no-connection',
        _frame(const VerifyLinkScreen(email: 'ana@example.com', code: '424242')),
        theme: theme,
        overrides: _overrides(auth),
        act: precacheWambi,
      );
    });
  }

  testWidgets('entry parity: the passkey failed, by day in English', (t) async {
    final auth = FakeAuthApi()
      ..failures['passkeySignIn'] = const AuthFailure(code: 'PASSKEY_NOT_FOUND', status: 400);
    await parityGolden(
      t,
      'signin-passkey-failed',
      _frame(const EmailScreen(passkeyLabel: 'Sign in with fingerprint')),
      theme: 'day',
      locale: const Locale('en'),
      overrides: _overrides(auth, passkeys: true),
      act: (t) async {
        await precacheWambi(t);
        await t.tap(_field('entry.passkey'));
        await t.pumpAndSettle();
        await _focusRinged(t, 'entry.passkey');
      },
    );
  });

  testWidgets('entry parity: the link rejected, by day in English', (t) async {
    final auth = FakeAuthApi()
      ..failures['verifyCode'] = const AuthFailure(code: 'OTP_EXPIRED', status: 400);
    await parityGolden(
      t,
      'verify-expired-day-english',
      _frame(const VerifyLinkScreen(email: 'ana@example.com', code: '424242')),
      theme: 'day',
      locale: const Locale('en'),
      overrides: _overrides(auth),
      act: precacheWambi,
    );
  });
}
