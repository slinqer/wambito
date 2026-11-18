// Settings' "Protect your data" block (phone-first spec 5.2): "N of 2" until a first step is done,
// then a quiet list; the passkey step only with passkey support; the no-PRF sentence.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/protect/protect_block.dart';
import 'package:wambito/protect/protect_status.dart';
import 'package:wambito/theme/theme.dart';
import 'package:wambito/ui/css_text.dart';
import 'package:wambito/ui/toast.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';

ProtectStatus statusOf({
  bool recoveryKey = false,
  bool passkey = false,
  bool offered = true,
  bool withoutPrf = false,
}) => ProtectStatus(
  recoveryKey: recoveryKey,
  passkey: passkey,
  passkeyOffered: offered,
  passkeyWithoutPrf: withoutPrf,
);

Future<void> pumpBlock(
  WidgetTester t,
  ProtectStatus? status, {
  Locale locale = const Locale('en'),
}) async {
  t.view
    ..physicalSize = const Size(824, 2400)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  // A fresh scope each time: a status of its own.
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(
    ProviderScope(
      overrides: [protectStatusProvider.overrideWith((ref) async => status)],
      child: uiApp(const SingleChildScrollView(child: ProtectBlock()), locale: locale),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shows 0 of 2 until a first step is done, then a quiet list without the count', (
    t,
  ) async {
    await pumpBlock(t, statusOf());
    expect(find.byKey(const Key('protect.block')), findsOneWidget);
    expect(find.text('0 of 2'), findsOneWidget);
    expect(find.byKey(const Key('protect.recovery')), findsOneWidget);
    expect(find.byKey(const Key('protect.passkey')), findsOneWidget);
    expect(find.byKey(const Key('protect.email')), findsOneWidget);

    await pumpBlock(t, statusOf(recoveryKey: true));
    expect(find.byKey(const Key('protect.count')), findsNothing);
    expect(find.byKey(const Key('protect.recovery')), findsNothing);
    expect(find.byKey(const Key('protect.recovery.done')), findsOneWidget);
    expect(find.byKey(const Key('protect.passkey')), findsOneWidget);
    expect(find.byKey(const Key('protect.email')), findsOneWidget);

    await pumpBlock(t, statusOf(passkey: true));
    expect(find.byKey(const Key('protect.count')), findsNothing);
    expect(find.byKey(const Key('protect.passkey.done')), findsOneWidget);
    expect(find.byKey(const Key('protect.recovery')), findsOneWidget);
  });

  testWidgets('the no-PRF line reads protectPasskeyNoPrf', (t) async {
    await pumpBlock(t, statusOf(withoutPrf: true));
    expect(find.byKey(const Key('protect.passkeyNoPrf')), findsOneWidget);
    String line() => t.widget<CssParagraph>(find.byKey(const Key('protect.passkeyNoPrf'))).text;
    expect(line(), 'This passkey can sign you in but cannot open your data. Add a recovery key.');
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await pumpBlock(t, statusOf(withoutPrf: true), locale: const Locale('es'));
    expect(line(), l10n.protectPasskeyNoPrf);
    // the passkey step stays open
    expect(find.byKey(const Key('protect.passkey')), findsOneWidget);
  });

  testWidgets('no line about PRF without a passkey', (t) async {
    await pumpBlock(t, statusOf());
    expect(find.byKey(const Key('protect.passkeyNoPrf')), findsNothing);
  });

  testWidgets('the passkey step is absent without passkey support', (t) async {
    await pumpBlock(t, statusOf(offered: false));
    expect(find.byKey(const Key('protect.passkey')), findsNothing);
    expect(find.byKey(const Key('protect.passkey.done')), findsNothing);
    expect(find.byKey(const Key('protect.recovery')), findsOneWidget);
    expect(find.text('0 of 2'), findsOneWidget);
  });

  testWidgets('nothing at all without a status (plain, email, vault closed)', (t) async {
    await pumpBlock(t, null);
    expect(find.byKey(const Key('protect.block')), findsNothing);
  });

  testWidgets('Add my email opens /progress', (t) async {
    t.view
      ..physicalSize = const Size(824, 2400)
      ..devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: SingleChildScrollView(child: ProtectBlock())),
        ),
        GoRoute(path: '/progress', builder: (_, _) => const Text('progress page')),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [protectStatusProvider.overrideWith((ref) async => statusOf())],
        child: MaterialApp.router(
          theme: nightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => ToastHost(animateBar: false, child: child!),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('protect.email')));
    await t.pumpAndSettle();
    expect(find.text('progress page'), findsOneWidget);
  });
}
