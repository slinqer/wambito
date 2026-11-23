// The iPhone's "Configurar en Atajos": the four steps of the ready-made shortcut on iOS 27 (once its
// iCloud link exists), else the guide to build the automation by hand (spec 2026-11-22, 3.4).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/capture_platform.dart';
import 'package:wambito/capture_auto/wallet_setup.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/settings/url_opener.dart';
import 'package:wambito/theme/theme.dart';
import 'package:wambito/ui/css_text.dart';
import 'package:wambito/ui/toast.dart';

import '../settings/harness.dart';
import 'fakes.dart';

const _link = 'https://www.icloud.com/shortcuts/0123456789abcdef0123456789abcdef';

Future<(FakeUrlOpener, FakeAutoCapturePlatform)> _open(
  WidgetTester t, {
  required int iosMajor,
  String shortcutUrl = _link,
}) async {
  final opener = FakeUrlOpener();
  final platform = FakeAutoCapturePlatform.iphone(iosMajor: iosMajor);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        urlOpenerProvider.overrideWithValue(opener),
        autoCapturePlatformProvider.overrideWithValue(platform),
      ],
      child: MaterialApp(
        theme: nightTheme,
        builder: (context, home) => ToastHost(child: home!),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () =>
                  showWalletSetup(context, iosMajor: iosMajor, shortcutUrl: shortcutUrl),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
  return (opener, platform);
}

void main() {
  testWidgets('on iOS 27 with the link: four steps and Instalar el atajo opens it', (t) async {
    final (opener, platform) = await _open(t, iosMajor: 27);
    for (var i = 1; i <= 4; i++) {
      expect(find.byKey(Key('walletSetup.step$i')), findsOneWidget);
    }
    expect(find.textContaining('Editar'), findsWidgets);
    await t.ensureVisible(find.byKey(const Key('walletSetup.install')));
    await t.tap(find.byKey(const Key('walletSetup.install')));
    await t.pumpAndSettle();
    expect(opener.opened, [Uri.parse(_link)]);
    expect(platform.callsNamed('openShortcuts'), isEmpty);
    expect(find.byKey(const Key('walletSetup.guide')), findsNothing);
  });

  testWidgets('without a link the guide shows, and it opens Shortcuts', (t) async {
    final (opener, platform) = await _open(t, iosMajor: 27, shortcutUrl: '');
    expect(find.byKey(const Key('walletSetup.guide')), findsOneWidget);
    expect(find.byKey(const Key('walletSetup.install')), findsNothing);
    await t.ensureVisible(find.byKey(const Key('walletSetup.openShortcuts')));
    await t.tap(find.byKey(const Key('walletSetup.openShortcuts')));
    await t.pumpAndSettle();
    expect(platform.callsNamed('openShortcuts'), hasLength(1));
    expect(opener.opened, isEmpty);
  });

  testWidgets('before iOS 27 the guide shows even with a link', (t) async {
    await _open(t, iosMajor: 26);
    expect(find.byKey(const Key('walletSetup.guide')), findsOneWidget);
    expect(find.byKey(const Key('walletSetup.install')), findsNothing);
    expect(find.textContaining('Transacción'), findsWidgets);
    // Each of the six steps is a paragraph of its own (one paragraph would collapse the breaks).
    expect(
      find.descendant(
        of: find.byKey(const Key('walletSetup.guide')),
        matching: find.byType(CssParagraph),
      ),
      findsNWidgets(6),
    );
  });
}
