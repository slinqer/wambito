// Italian and Portuguese run 10-25% longer than Spanish. On a 360 px phone with the font at 130%
// the key labels must not overflow (a RenderFlex error) and must not be cut off with an ellipsis
// where the web would not cut them (spec §3): the bottom bar, the home tabs, the account menu, the
// add sheet's buttons, the toast with its undo, the settings rows and the capture sheet.
import 'package:wambito/settings/category_screen.dart' show settingsCategoryTitle;
import 'package:wambito/settings/settings_categories.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart' show PasskeyItem;
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/security/screen_lock.dart';
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/settings/settings_parts.dart' show SettingsRow;
import 'package:wambito/ui/toast.dart';
import 'package:wambito/vault/preview.dart' show isPreviewProvider;

import '../add/fakes.dart';
import '../entry/fakes.dart';
import '../home/home_harness.dart';
import '../settings/harness.dart';
import '../settings/security/fake_security.dart';

/// Words a person typed (the fakes' category names), which are cut off in every language.
const _data = {'Supermercado', 'Hogar', 'Arriendo'};

/// The text of every paragraph on screen that was cut off (ellipsis or clip) by its `maxLines`.
List<String> _cutOff(WidgetTester tester) {
  final cut = <String>[];
  void visit(RenderObject object) {
    if (object is RenderParagraph &&
        object.didExceedMaxLines &&
        !_data.contains(object.text.toPlainText())) {
      cut.add(object.text.toPlainText());
    }
    object.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  return cut;
}

/// Every paragraph on screen.
List<RenderParagraph> _paragraphs(WidgetTester tester) {
  final all = <RenderParagraph>[];
  void visit(RenderObject object) {
    if (object is RenderParagraph) all.add(object);
    object.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  return all;
}

/// No layout error was reported, and none of [labels] is cut off where it is drawn (buttons draw
/// their label in capitals, as the web's CSS does, so the match ignores case).
void _expectWhole(WidgetTester tester, List<String> labels, {String? where}) {
  expect(tester.takeException(), isNull, reason: where);
  final paragraphs = _paragraphs(tester);
  for (final label in labels) {
    final drawn = paragraphs.where(
      (p) => p.text.toPlainText().toLowerCase() == label.toLowerCase(),
    );
    expect(drawn, isNotEmpty, reason: '"$label" is on screen ${where ?? ''}');
    for (final p in drawn) {
      expect(p.didExceedMaxLines, isFalse, reason: '"$label" is cut off ${where ?? ''}');
    }
  }
  expect(_cutOff(tester), isEmpty, reason: 'text cut off ${where ?? ''}');
}

Future<SettingsEnv> _pump(WidgetTester tester, Locale locale, {String? location}) async {
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final env = await pumpSettingsApp(tester, locale: locale, location: location);
  tester.view
    ..physicalSize = const Size(360, 640)
    ..devicePixelRatio = 1;
  await tester.pumpAndSettle();
  return env;
}

/// Home with budgets and movements, on the 360 px phone at 130%.
Future<void> _pumpHome(WidgetTester tester, Locale locale, {double height = 640}) {
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final server = monthWithBudgets();
  return pumpHome(
    tester,
    server,
    addRepo: FakeAddRepository(server),
    locale: locale,
    size: Size(360, height),
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

void main() {
  for (final (language, locale) in [('it', Locale('it', 'IT')), ('pt', Locale('pt', 'PT'))]) {
    group('$language at 360 px, text scale 1.3', () {
      testWidgets('the bottom bar and the home tabs keep their words whole', (tester) async {
        await _pumpHome(tester, locale);
        final l10n = _l10n(tester);
        expect(l10n.localeName, startsWith(language));
        _expectWhole(tester, [
          l10n.navHome,
          l10n.navInsights,
          l10n.homeBudgetsTab,
          l10n.homeMovements,
        ], where: 'on home');
        await tester.tap(find.text(l10n.homeMovements));
        await tester.pumpAndSettle();
        _expectWhole(tester, [l10n.homeBudgetsTab, l10n.homeMovements], where: 'on the movements');
      });

      testWidgets('the account menu keeps Ricorrenti / Recorrentes and Impostazioni / Definições '
          'whole', (tester) async {
        await _pump(tester, locale);
        final l10n = _l10n(tester);
        await openAccountMenu(tester);
        _expectWhole(tester, [
          l10n.homeMenuRecurring,
          l10n.homeMenuCategories,
          l10n.settingsOpenLabel,
        ], where: 'in the account menu');
      });

      testWidgets('the add sheet keeps its buttons whole, closed and with more options', (
        tester,
      ) async {
        // 800 px tall, so that "More options" is not under the keypad's dock; the width and the
        // font are what the words depend on.
        await _pumpHome(tester, locale, height: 800);
        final l10n = _l10n(tester);
        await tester.tap(find.byKey(const Key('home.add')));
        await tester.pumpAndSettle();
        _expectWhole(tester, [
          l10n.addTitleExpense,
          l10n.addClose,
          l10n.addKindExpense,
          l10n.addKindIncome,
          l10n.addMoreOptions,
          l10n.addSave,
        ], where: 'in the add sheet');
        await tester.tap(find.byKey(const Key('add.more')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('add.pending')), findsOneWidget, reason: 'more options opened');
        _expectWhole(tester, [
          l10n.addMoreOptions,
          l10n.addDateLabel,
          l10n.addPendingLabel,
          l10n.addNoteLabel,
          l10n.addSave,
        ], where: 'with more options');
      });

      testWidgets('the toast with its two actions fits, and so do the undone and error ones', (
        tester,
      ) async {
        await _pumpHome(tester, locale);
        final l10n = _l10n(tester);
        final toasts = ToastHost.of(tester.element(find.byType(Scaffold).first));
        final saved = l10n.addSavedExpense('Supermercado', '−1.234,56 €');
        toasts.say(
          saved,
          extraLabel: l10n.addNameIt,
          onExtra: () {},
          actionLabel: l10n.undo,
          onAction: () {},
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));
        _expectWhole(tester, [l10n.addNameIt, l10n.undo], where: 'in the saved toast');
        toasts.say(l10n.addUndone('Supermercado'), error: true);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });

      for (final scale in [1.0, 1.3]) {
        testWidgets('the settings menu has no overflow at text scale $scale', (tester) async {
          await _pump(tester, locale, location: '/settings');
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          // Ellipsis on a line is fine; a RenderFlex overflow is not.
          expect(tester.takeException(), isNull);
        });
      }

      for (final category in SettingsCategory.values) {
        testWidgets('every ${category.name} row is drawn whole, top to bottom', (tester) async {
          await _pump(tester, locale, location: category.path);
          final l10n = _l10n(tester);
          expect(tester.takeException(), isNull);
          final seen = <String>{};
          for (var i = 0; i < 40; i++) {
            _expectWhole(tester, const [], where: 'in ${category.name} (screen $i)');
            seen.addAll(
              tester
                  .widgetList<Text>(find.byType(Text))
                  .map((text) => text.data ?? text.textSpan?.toPlainText() ?? ''),
            );
            final scrollable = find.byType(Scrollable).first;
            final before = tester.state<ScrollableState>(scrollable).position.pixels;
            await tester.drag(scrollable, const Offset(0, -300));
            await tester.pumpAndSettle();
            final after = tester.state<ScrollableState>(scrollable).position.pixels;
            if (after == before) break;
          }
          expect(
            seen,
            contains(settingsCategoryTitle(l10n, category)),
            reason: 'the page was read from its top',
          );
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('an encrypted account\'s account page has no overflow and rows of one line', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final auth = FakeAuthApi()
          ..passkeyItems.add(
            PasskeyItem(
              id: 'pk-1',
              credentialId: 'cred-2',
              name: 'Pixel 8',
              createdAt: DateTime.utc(2026, 11, 3),
              synced: true,
            ),
          );
        await pumpSettingsApp(
          tester,
          locale: locale,
          location: '/settings/account',
          auth: auth,
          passkeysSupported: true,
          overrides: [
            isPreviewProvider.overrideWithValue(true),
            // the passkey has no wrap, so its "Turn on" row shows too
            securityApiProvider.overrideWithValue(FakeSecurity(snapshotOf(unreadable: 3))),
            screenLockProvider.overrideWithValue(FakeLock(LockCheck.passed)),
          ],
        );
        tester.view
          ..physicalSize = const Size(360, 640)
          ..devicePixelRatio = 1;
        await tester.pumpAndSettle();
        final walked = <String>{};
        for (var i = 0; i < 40; i++) {
          expect(tester.takeException(), isNull, reason: 'overflow on screen $i');
          for (final element in find.byType(SettingsRow).evaluate()) {
            final key = element.widget.key;
            walked.add('$key');
            final box = element.renderObject! as RenderBox;
            expect(box.size.height, lessThanOrEqualTo(76), reason: '$key');
          }
          final scrollable = find.byType(Scrollable).first;
          final before = tester.state<ScrollableState>(scrollable).position.pixels;
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pumpAndSettle();
          final after = tester.state<ScrollableState>(scrollable).position.pixels;
          if (after == before) break;
        }
        for (final name in [
          'security.connect',
          'security.newKey',
          'security.changeKeys',
          'settings.passkeys.turnOn.pk-1',
          'settings.delete',
        ]) {
          expect(walked.any((k) => k.contains(name)), isTrue, reason: '$name was walked');
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('the capture sheet keeps its words whole', (tester) async {
        await _pump(tester, locale);
        final l10n = _l10n(tester);
        await tester.tap(find.byKey(const Key('home.capture')));
        // Something on the capture sheet keeps moving (a spinner): frames, not a settle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(_cutOff(tester), isEmpty, reason: 'text cut off in the capture sheet');
        expect(l10n.captureTitle, isNotEmpty);
      });
    });
  }
}
