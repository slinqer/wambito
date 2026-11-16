import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/theme/text_styles.dart';
import 'package:wambito/theme/theme.dart';
import 'package:wambito/theme/tokens.g.dart';

import '../support/fonts.dart';

/// The web's stylesheet and components, relative to apps/mobile (where `flutter test` runs).
const _appCss = '../web/app/styles/app.css';
const _sheetTsx = '../web/app/ui/Sheet.tsx';
const _confirmSheetTsx = '../web/app/ui/ConfirmSheet.tsx';
const _addSheetTsx = '../web/app/features/add-transaction/AddTransactionSheet.tsx';
const _homeTsx = '../web/app/features/home/Home.tsx';
const _homeHeaderTsx = '../web/app/features/home/HomeHeader.tsx';
const _signInScreenTsx = '../web/app/features/sign-in/SignInScreen.tsx';
const _signInTsx = '../web/app/features/sign-in/SignIn.tsx';
const _tokensCss = '../web/app/styles/tokens.css';
const _settingsTsx = '../web/app/features/settings/Settings.tsx';
const _settingsPartsTsx = '../web/app/features/settings/parts.tsx';

/// The declarations of `selector { ... }` in app.css, the first rule with exactly that selector.
Map<String, String> _rule(String selector) {
  final css = File(_appCss).readAsStringSync();
  final match = RegExp('\n  ${RegExp.escape(selector)} \\{([^}]*)\\}').firstMatch(css);
  if (match == null) fail('No rule "$selector" in $_appCss');
  return {
    for (final line in match.group(1)!.split(';'))
      if (line.contains(':'))
        line.substring(0, line.indexOf(':')).trim(): line.substring(line.indexOf(':') + 1).trim(),
  };
}

double _px(String value) => double.parse(value.replaceAll('px', ''));

void main() {
  setUpAll(loadAppFonts);

  group('the families', () {
    test('the display and text families are Fredoka and Nunito, as in tokens.css', () {
      // tokens.css:119-121 --font-display "Fredoka", --font-text "Nunito".
      final tokens = File(_tokensCss).readAsStringSync();
      expect(tokens, contains('--font-display: "Fredoka"'));
      expect(tokens, contains('--font-text: "Nunito"'));
      expect(LkText.displayFamily, 'Fredoka');
      expect(LkText.textFamily, 'Nunito');
    });

    test('the theme sets Nunito at the weight the web\'s body has, 700', () {
      // app.css:50-56 body { font-family: var(--font-text); font-weight: 700 }
      for (final theme in [nightTheme, dayTheme]) {
        for (final style in [
          theme.textTheme.bodyLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.titleMedium,
          theme.textTheme.labelLarge,
        ]) {
          expect(style!.fontFamily, 'Nunito');
          expect(style.fontWeight, FontWeight.w700);
        }
      }
    });

    test('the bundled fonts really draw: the real faces measure differently from Ahem', () {
      double width(String family, FontWeight weight) {
        final painter = TextPainter(
          text: TextSpan(
            text: 'Supermercado 1.234',
            style: TextStyle(fontFamily: family, fontSize: 20, fontWeight: weight),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        return painter.width;
      }

      // Ahem is 1em per glyph: 18 characters at 20 px is 360.
      expect(width('Nunito', FontWeight.w700), isNot(360));
      expect(width('Fredoka', FontWeight.w700), isNot(360));
      // The weights are real: a variable font follows the weight asked for.
      expect(width('Nunito', FontWeight.w900), greaterThan(width('Nunito', FontWeight.w600)));
      // (Fredoka's advances narrow a little as it gets bolder.)
      expect(width('Fredoka', FontWeight.w700), isNot(width('Fredoka', FontWeight.w500)));
    });
  });

  group('each style has the size, weight, height and spacing of its web source', () {
    test('display: the keypad\'s amount, Fredoka 36px 700', () {
      // app.css:409-414 .lk-amount-display
      final css = _rule('.lk-amount-display');
      expect(css['font-family'], 'var(--font-display)');
      expect(css['font-size'], '36px');
      expect(css['font-weight'], '700');
      expect(LkText.display.fontFamily, 'Fredoka');
      expect(LkText.display.fontSize, 36);
      expect(LkText.display.fontWeight, FontWeight.w700);
      // No line-height declared: it inherits Tailwind's preflight 1.5.
      expect(LkText.display.height, 1.5);
      expect(LkText.display.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('amountXl: the hero amount, Fredoka 38px 700, line height 1.05', () {
      // app.css:185-191 .lk-hero-amount
      final css = _rule('.lk-hero-amount');
      expect(css['font-family'], 'var(--font-display)');
      expect(css['font-size'], '38px');
      expect(css['font-weight'], '700');
      expect(css['line-height'], '1.05');
      expect(css['font-variant-numeric'], 'tabular-nums');
      expect(LkText.amountXl.fontFamily, 'Fredoka');
      expect(LkText.amountXl.fontSize, 38);
      expect(LkText.amountXl.fontWeight, FontWeight.w700);
      expect(LkText.amountXl.height, 1.05);
      expect(LkText.amountXl.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('amount: a row\'s amount, Fredoka 14px 600, tabular', () {
      // app.css:271-277 .lk-amount
      final css = _rule('.lk-amount');
      expect(css['font-family'], 'var(--font-display)');
      expect(css['font-size'], '14px');
      expect(css['font-weight'], '600');
      expect(css['font-variant-numeric'], 'tabular-nums');
      expect(css['white-space'], 'nowrap');
      expect(LkText.amount.fontFamily, 'Fredoka');
      expect(LkText.amount.fontSize, 14);
      expect(LkText.amount.fontWeight, FontWeight.w600);
      // No line-height declared: it inherits Tailwind's preflight 1.5.
      expect(LkText.amount.height, 1.5);
      expect(LkText.amount.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('title: a sheet\'s title, Fredoka 24px 700, line height 1.15', () {
      // Sheet.tsx:295 className="m-0 font-display text-[24px] leading-[1.15] font-bold"
      final source = File(_sheetTsx).readAsStringSync();
      expect(source, contains('m-0 font-display text-[24px] leading-[1.15] font-bold'));
      expect(LkText.title.fontFamily, 'Fredoka');
      expect(LkText.title.fontSize, 24);
      expect(LkText.title.fontWeight, FontWeight.w700);
      expect(LkText.title.height, 1.15);
    });

    test('body: running text, Nunito 15px 700, the preflight\'s line height 1.5', () {
      // ConfirmSheet.tsx:54 <p className="m-0 text-[15px] text-ink">, with app.css:55 weight 700
      // and tailwindcss preflight.css:30 `line-height: 1.5` on html.
      expect(File(_confirmSheetTsx).readAsStringSync(), contains('m-0 text-[15px] text-ink'));
      expect(_rule('body')['font-weight'], '700');
      expect(LkText.body.fontFamily, 'Nunito');
      expect(LkText.body.fontSize, 15);
      expect(LkText.body.fontWeight, FontWeight.w700);
      expect(LkText.body.height, 1.5);
    });

    test('label: a row\'s title, Nunito 13px 800', () {
      // app.css:253-259 .lk-rowtop
      final css = _rule('.lk-rowtop');
      expect(css['font-size'], '13px');
      expect(css['font-weight'], '800');
      expect(LkText.label.fontFamily, 'Nunito');
      expect(LkText.label.fontSize, 13);
      expect(LkText.label.fontWeight, FontWeight.w800);
      expect(LkText.label.height, 1.5);
    });

    test('caption: a row\'s status line, Nunito 11px 800', () {
      // app.css:260-264 .lk-status
      final css = _rule('.lk-status');
      expect(css['font-size'], '11px');
      expect(css['font-weight'], '800');
      expect(LkText.caption.fontFamily, 'Nunito');
      expect(LkText.caption.fontSize, 11);
      expect(LkText.caption.fontWeight, FontWeight.w800);
      expect(LkText.caption.height, 1.5);
    });

    test('eyebrow: a day header, Nunito 11px 900, 0.07em apart, upper case', () {
      // app.css:301-310 .lk-overline
      final css = _rule('.lk-overline');
      expect(css['font-size'], '11px');
      expect(css['font-weight'], '900');
      expect(css['letter-spacing'], '0.07em');
      expect(css['text-transform'], 'uppercase');
      expect(LkText.eyebrow.fontFamily, 'Nunito');
      expect(LkText.eyebrow.fontSize, 11);
      expect(LkText.eyebrow.fontWeight, FontWeight.w900);
      // 0.07em of 11px, in logical pixels.
      expect(LkText.eyebrow.letterSpacing, closeTo(0.07 * 11, 1e-9));
      expect(LkText.eyebrow.height, 1.5);
      expect(LkText.upperCase('hoy · mar 21'), 'HOY · MAR 21');
    });

    test('screenTitle: the entry screens\' title, Fredoka 28px 700 on leading-tight', () {
      // SignInScreen.tsx ScreenTitle: font-display text-[28px] leading-tight font-bold
      final source = File(_signInScreenTsx).readAsStringSync();
      expect(source, contains('font-display text-[28px] leading-tight font-bold'));
      expect(LkText.screenTitle.fontFamily, 'Fredoka');
      expect(LkText.screenTitle.fontSize, 28);
      expect(LkText.screenTitle.fontWeight, FontWeight.w700);
      // Tailwind's leading-tight is 1.25.
      expect(LkText.screenTitle.height, 1.25);
    });

    test('copy, note and labelSm: the paragraphs and labels of the sign-in screens', () {
      final source = File(_signInTsx).readAsStringSync();
      // A paragraph with no size of its own is the body's 16px.
      expect(source, contains('<p className="text-center text-ink-muted">{t("lead")}</p>'));
      expect(LkText.copy.fontSize, 16);
      expect(LkText.copy.fontWeight, FontWeight.w700);
      expect(LkText.copy.height, 1.5);
      // The note under the form and a field's error: text-[15px].
      expect(source, contains('className="text-center text-[15px] text-ink-muted"'));
      expect(File(_signInScreenTsx).readAsStringSync(), contains('text-[15px] text-over'));
      expect(LkText.note.fontSize, 15);
      expect(LkText.note.height, 1.5);
      // The label of a field: text-sm, which Tailwind gives a 20px line.
      expect(source, contains('className="text-sm text-ink-muted"'));
      expect(LkText.labelSm.fontSize, 14);
      expect(LkText.labelSm.fontWeight, FontWeight.w700);
      expect(LkText.labelSm.height! * 14, closeTo(20, 1e-9));
    });

    test('pageTitle and sectionTitle: Settings\' title and its cards\' titles', () {
      // Settings.tsx: the h1 has a size and a weight, no leading of its own.
      expect(
        File(_settingsTsx).readAsStringSync(),
        contains('m-0 font-display text-[28px] font-bold text-ink'),
      );
      expect(LkText.pageTitle.fontFamily, 'Fredoka');
      expect(LkText.pageTitle.fontSize, 28);
      expect(LkText.pageTitle.fontWeight, FontWeight.w700);
      expect(LkText.pageTitle.height, 1.5);
      // parts.tsx SettingsSection: the h2 is leading-tight (1.25).
      expect(
        File(_settingsPartsTsx).readAsStringSync(),
        contains('m-0 font-display text-[20px] font-bold leading-tight'),
      );
      expect(LkText.sectionTitle.fontFamily, 'Fredoka');
      expect(LkText.sectionTitle.fontSize, 20);
      expect(LkText.sectionTitle.fontWeight, FontWeight.w700);
      expect(LkText.sectionTitle.height, 1.25);
    });

    test('codeBox: a digit of the sign-in code, Fredoka 26px 700 with tabular figures', () {
      // app.css .lk-code-box
      final css = _rule('.lk-code-box');
      expect(css['font-family'], 'var(--font-display)');
      expect(css['font-size'], '26px');
      expect(css['font-weight'], '700');
      expect(css['font-variant-numeric'], 'tabular-nums');
      expect(css['height'], '56px');
      expect(LkText.codeBox.fontFamily, 'Fredoka');
      expect(LkText.codeBox.fontSize, 26);
      expect(LkText.codeBox.fontWeight, FontWeight.w700);
      expect(LkText.codeBox.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('logo: the wordmark, Fredoka 22px 700, line height 1', () {
      // app.css:87-96 .lk-logo
      final css = _rule('.lk-logo');
      expect(css['font-family'], 'var(--font-display)');
      expect(css['font-size'], '22px');
      expect(css['font-weight'], '700');
      expect(css['line-height'], '1');
      expect(LkText.logo.fontFamily, 'Fredoka');
      expect(LkText.logo.fontSize, 22);
      expect(LkText.logo.fontWeight, FontWeight.w700);
      expect(LkText.logo.height, 1);
    });

    test('heroLabel: Nunito 13px 800 (the utility\'s 13px over the class\'s 12px)', () {
      // Home.tsx: <h1 id={labelId} className="lk-hero-label m-0 text-[13px]">; app.css:180-184
      expect(
        File(_homeTsx).readAsStringSync(),
        contains('className="lk-hero-label m-0 text-[13px]"'),
      );
      final css = _rule('.lk-hero-label');
      expect(css['font-size'], '12px');
      expect(css['font-weight'], '800');
      expect(LkText.heroLabel.fontFamily, 'Nunito');
      expect(LkText.heroLabel.fontSize, 13);
      expect(LkText.heroLabel.fontWeight, FontWeight.w800);
      expect(LkText.heroLabel.height, 1.5);
    });

    test('meta: the line under the hero\'s bar, Nunito 11px 800', () {
      // app.css:193-200 .lk-hero-meta
      final css = _rule('.lk-hero-meta');
      expect(css['font-size'], '11px');
      expect(css['font-weight'], '800');
      expect(css['margin-top'], '6px');
      expect(LkText.meta.fontFamily, 'Nunito');
      expect(LkText.meta.fontSize, 11);
      expect(LkText.meta.fontWeight, FontWeight.w800);
      expect(LkText.meta.height, 1.5);
    });

    test(
      'bodySm, cardTitle, cardLead: the home cards and menu, as Home.tsx and HomeHeader.tsx',
      () {
        final home = File(_homeTsx).readAsStringSync();
        // Home.tsx: Transactions' empty message and NoCategories' lead, the menu's entries.
        expect(home, contains('className="m-0 text-[14px] font-bold text-ink-muted"'));
        expect(File(_homeHeaderTsx).readAsStringSync(), contains('text-[14px] font-bold text-ink'));
        expect(LkText.bodySm.fontSize, 14);
        expect(LkText.bodySm.fontWeight, FontWeight.w700);
        // Home.tsx: the nudge's h2 `text-[14px] font-extrabold text-ink`, its p `text-[12px] font-bold`.
        expect(home, contains('text-[14px] font-extrabold text-ink'));
        expect(home, contains('className="m-0 text-[12px] font-bold text-ink-muted"'));
        expect(LkText.cardTitle.fontSize, 14);
        expect(LkText.cardTitle.fontWeight, FontWeight.w800);
        expect(LkText.cardLead.fontSize, 12);
        expect(LkText.cardLead.fontWeight, FontWeight.w700);
        for (final style in [LkText.bodySm, LkText.cardTitle, LkText.cardLead]) {
          expect(style.fontFamily, 'Nunito');
          expect(style.height, 1.5);
        }
      },
    );

    test(
      'fieldLabel: the captions of the add sheet\'s date and note, as AddTransactionSheet.tsx',
      () {
        final sheet = File(_addSheetTsx).readAsStringSync();
        // The date's and the note's `<label>`: `text-[13px] font-bold text-ink-muted`.
        expect(
          'text-[13px] font-bold text-ink-muted'.allMatches(sheet).length,
          greaterThanOrEqualTo(2),
        );
        expect(LkText.fieldLabel.fontFamily, 'Nunito');
        expect(LkText.fieldLabel.fontSize, 13);
        expect(LkText.fieldLabel.fontWeight, FontWeight.w700);
        expect(LkText.fieldLabel.height, 1.5);
      },
    );

    test('the CSS sizes are read in px: sanity of the parser', () {
      expect(_px('36px'), 36);
    });
  });

  group('default text takes the ink of its own theme', () {
    // tokens.css --ink: #f3f0ff at night, #221a47 by day; app.css:50-56 body { color: var(--ink) }.
    for (final (name, theme, ink) in [
      ('night', nightTheme, WambitoTokens.night.ink),
      ('day', dayTheme, WambitoTokens.day.ink),
    ]) {
      testWidgets('a plain Text and a dialog\'s title and content are the $name ink', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    const Text('plain', key: Key('plain')),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const AlertDialog(
                          title: Text('title', key: Key('title')),
                          content: Text('content', key: Key('content')),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        for (final key in ['plain', 'title', 'content']) {
          final text = tester.widget<Text>(find.byKey(Key(key)));
          final style = DefaultTextStyle.of(tester.element(find.byKey(Key(key)))).style
              .merge(text.style);
          expect(style.color, ink, reason: '$key in $name');
        }
      });
    }

    test('every Material text style carries the ink, never Material\'s black or white', () {
      for (final (theme, ink) in [
        (nightTheme, WambitoTokens.night.ink),
        (dayTheme, WambitoTokens.day.ink),
      ]) {
        final t = theme.textTheme;
        for (final style in [
          t.displayLarge, t.displayMedium, t.displaySmall, t.headlineLarge, t.headlineMedium,
          t.headlineSmall, t.titleLarge, t.titleMedium, t.titleSmall, t.bodyLarge, t.bodyMedium,
          t.bodySmall, t.labelLarge, t.labelMedium, t.labelSmall, //
        ]) {
          expect(style!.color, ink);
        }
      }
    });
  });

  testWidgets('the styles draw with the fonts they name, not with Ahem', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Text('Quedan', key: const Key('a'), style: LkText.amountXl),
            Text('Quedan', key: const Key('b'), style: LkText.label),
          ],
        ),
      ),
    );
    // Ahem would make 6 glyphs exactly 6 em wide.
    expect(tester.getSize(find.byKey(const Key('a'))).width, isNot(6 * 38));
    expect(tester.getSize(find.byKey(const Key('b'))).width, isNot(6 * 13));
  });
}
