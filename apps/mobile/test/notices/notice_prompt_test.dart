import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/add/add_sheet.dart';
import 'package:wambito/launch/launch_links.dart';
import 'package:wambito/notices/notice_backend.dart';
import 'package:wambito/notices/notice_platform.dart';

import '../launch/launch_links_test.dart' show FakeLaunchLinks;
import '../settings/harness.dart';
import 'fakes.dart';

void main() {
  /// The app with the real dialog, and a platform that has not been asked yet.
  Future<(SettingsEnv, FakeNoticePlatform)> pump(
    WidgetTester tester, {
    bool guest = false,
    bool hasRecurring = true,
    Locale locale = const Locale('es'),
    bool systemAnswer = true,
  }) async {
    final platform = FakeNoticePlatform(systemAnswer: systemAnswer);
    final env = await pumpSettingsApp(
      tester,
      guest: guest,
      locale: locale,
      overrides: [
        noticePlatformProvider.overrideWithValue(platform),
        noticeBackendProvider.overrideWithValue(FakeNoticeBackend(hasRecurring: hasRecurring)),
      ],
    );
    // The question stays on screen until it is answered, so no waiting for the sync to be idle.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    return (env, platform);
  }

  testWidgets('one sentence on why, in the app, before Android\'s own prompt', (tester) async {
    final (_, platform) = await pump(tester);
    expect(find.byKey(const Key('notices.ask')), findsOneWidget);
    expect(find.byKey(const Key('notices.askWhy')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('notices.askWhy'))).data,
      'Así Wambito puede avisarte a las 9:00 los días en que vence un pago recurrente.',
    );
    expect(
      platform.callsNamed('requestPermission'),
      isEmpty,
      reason: 'Android is asked after "Permitir"',
    );

    await tester.tap(find.byKey(const Key('notices.askAllow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsNothing);
    expect(platform.callsNamed('requestPermission'), hasLength(1));
  });

  testWidgets('"Ahora no" asks Android nothing and closes', (tester) async {
    final (_, platform) = await pump(tester);
    await tester.tap(find.byKey(const Key('notices.askLater')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsNothing);
    expect(platform.callsNamed('requestPermission'), isEmpty);
  });

  testWidgets('for a guest, the sentence is about the warning', (tester) async {
    await pump(tester, guest: true, hasRecurring: false);
    expect(
      tester.widget<Text>(find.byKey(const Key('notices.askWhy'))).data,
      'Así Wambito puede avisarte si pasan 45 días sin abrirlo y tu cuenta no tiene correo, antes de que se borren tus datos.',
    );
  });

  testWidgets('on iOS, the sentence says around 9:00', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('notices.askWhy'))).data,
        'Así Wambito puede avisarte hacia las 9:00 los días en que vence un pago recurrente.',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('in English', (tester) async {
    await pump(tester, locale: const Locale('en'));
    expect(
      tester.widget<Text>(find.byKey(const Key('notices.askWhy'))).data,
      'So Wambito can tell you at 9:00 on the days a recurring payment is due.',
    );
    final ask = find.byKey(const Key('notices.ask'));
    expect(find.descendant(of: ask, matching: find.text('NOT NOW')), findsOneWidget);
    expect(find.descendant(of: ask, matching: find.text('ALLOW NOTICES')), findsOneWidget);
  });

  testWidgets(
    'the question waits for home, with no sheet over it, and does not appear over Settings',
    (tester) async {
      final links = FakeLaunchLinks('wambito://add');
      final platform = FakeNoticePlatform();
      final env = await pumpSettingsApp(
        tester,
        overrides: [
          launchLinkSourceProvider.overrideWithValue(links),
          noticePlatformProvider.overrideWithValue(platform),
          noticeBackendProvider.overrideWithValue(FakeNoticeBackend(hasRecurring: true)),
        ],
      );
      await tester.pump(const Duration(seconds: 2));
      // The add sheet is open over home: no question over it.
      expect(find.byType(AddSheet), findsOneWidget);
      expect(find.byKey(const Key('notices.ask')), findsNothing);

      // The sheet closed: now home is free, and the question comes.
      Navigator.of(env.router.routerDelegate.navigatorKey.currentContext!).pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notices.ask')), findsOneWidget);
    },
  );

  testWidgets('not over Settings: it waits until the person is back on home', (tester) async {
    final platform = FakeNoticePlatform();
    final env = await pumpSettingsApp(
      tester,
      location: '/settings',
      overrides: [
        noticePlatformProvider.overrideWithValue(platform),
        noticeBackendProvider.overrideWithValue(FakeNoticeBackend(hasRecurring: true)),
      ],
    );
    // The pass that started on home found the person elsewhere; the next one (the app coming back)
    // finds them on Settings and waits.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('notices.ask')), findsNothing);
    env.router.go('/');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsOneWidget);
  });

  testWidgets('a link that arrives while it is up closes it without counting it as "Ahora no"', (
    tester,
  ) async {
    final links = FakeLaunchLinks();
    final platform = FakeNoticePlatform();
    final env = await pumpSettingsApp(
      tester,
      overrides: [
        launchLinkSourceProvider.overrideWithValue(links),
        noticePlatformProvider.overrideWithValue(platform),
        noticeBackendProvider.overrideWithValue(FakeNoticeBackend(hasRecurring: true)),
      ],
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsOneWidget);

    links.open('wambito://due');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsNothing);
    expect(platform.callsNamed('requestPermission'), isEmpty);
    expect(env.flags['notice.permission.asked']?.value, isNot(true), reason: 'not an answer');

    // Asked again at the next chance (the app coming back), on home.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsOneWidget);
  });

  testWidgets('tapping outside the question does not answer it', (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsOneWidget);
  });

  testWidgets('it is the web\'s sheet: no Cerrar, and Escape does not answer it', (tester) async {
    await pump(tester);
    expect(find.text('CERRAR'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsOneWidget);
  });

  testWidgets('the back button is "Ahora no": Android is not asked, and it is not asked again', (
    tester,
  ) async {
    final (env, platform) = await pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notices.ask')), findsNothing);
    expect(platform.callsNamed('requestPermission'), isEmpty);
    expect(env.flags['notice.permission.asked']?.value, isTrue, reason: 'an answer');
  });
}
