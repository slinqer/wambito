import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _locales = ['es', 'en', 'it', 'pt'];
const _steps = ['Pay', 'Reads', 'Decide', 'Learns', 'Next'];

/// A language is never named in the capture copy (the Global Constraints' word list).
final _languageWords = RegExp(
  r'portugu[eéê]s|portuguese|portoghese|espa[nñ]ol|spanish|espanhol|spagnolo|ingl[eéê]s|english|'
  r'inglese|italiano|italian|idiomas?|languages?|l[ií]nguas?|lingue',
  caseSensitive: false,
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

Map<String, String> _how(String locale) => {
      for (final e in _arb(locale).entries)
        if (e.key.startsWith('autoCaptureHow') && e.value is String) e.key: e.value as String,
    };

Map<String, dynamic> _web(String locale) {
  final json = jsonDecode(File('../web/app/i18n/messages/$locale.json').readAsStringSync())
      as Map<String, dynamic>;
  return (json['landing'] as Map<String, dynamic>)['capture'] as Map<String, dynamic>;
}

void main() {
  test('the language words match every accented and plural form', () {
    const forms = [
      'portugués', 'português', 'portugues', 'portuguese', 'portoghese', 'español', 'espanol',
      'spanish', 'espanhol', 'spagnolo', 'inglés', 'inglês', 'ingles', 'english', 'inglese',
      'italiano', 'italian', 'idioma', 'idiomas', 'language', 'languages', 'lingua', 'lingue',
      'língua', 'línguas', 'linguas',
    ];
    for (final form in forms) {
      expect(_languageWords.hasMatch('en $form.'), isTrue, reason: form);
    }
  });

  final es = _how('es');

  test('every autoCaptureHow key exists in the four ARBs', () {
    expect(es, isNotEmpty);
    for (final locale in _locales) {
      expect(_how(locale).keys.toSet(), es.keys.toSet(), reason: locale);
    }
  });

  test('no autoCaptureHow value names a language', () {
    for (final locale in _locales) {
      for (final e in _how(locale).entries) {
        expect(_languageWords.hasMatch(e.value), isFalse, reason: '$locale ${e.key}');
      }
    }
  });

  test('the last step names the sources and the platform', () {
    for (final locale in _locales) {
      final body = _how(locale)['autoCaptureHowNextBody']!;
      expect(body, contains('Revolut'));
      expect(body, contains('Google Wallet'));
      expect(body, contains('Android'));
    }
  });

  test('step titles, bodies and demo words equal the web copy in each language', () {
    const demo = {
      'Registered': 'registered',
      'Review': 'review',
      'Today': 'today',
      'Notice': 'notice',
      'Ok': 'ok',
      'Change': 'change',
      'OtherExpenses': 'other_expenses',
      'OtherIncome': 'other_income',
      'EatingOut': 'eating_out',
    };
    for (final locale in _locales) {
      final web = _web(locale);
      final app = _how(locale);
      final webSteps = web['steps'] as Map<String, dynamic>;
      for (final step in _steps) {
        final webStep = webSteps[step.toLowerCase()] as Map<String, dynamic>;
        expect(app['autoCaptureHow${step}Title'], webStep['title'], reason: '$locale $step title');
        expect(app['autoCaptureHow${step}Body'], webStep['body'], reason: '$locale $step body');
      }
      final webDemo = web['demo'] as Map<String, dynamic>;
      for (final e in demo.entries) {
        expect(app['autoCaptureHow${e.key}'], webDemo[e.value], reason: '$locale ${e.key}');
      }
    }
  });

  test('the disclosure says what is read and that only the amount, merchant, date and app leave',
      () {
    // Google Play's prominent disclosure before notification access: what is read, what is sent.
    const sent = {
      'es': ['Solo', 'monto', 'comercio', 'fecha', 'app', 'salen de tu teléfono'],
      'en': ['Only', 'amount', 'merchant', 'date', 'app', 'leave your phone'],
      'it': ['Solo', 'importo', 'esercente', 'data', 'app', 'lasciano il tuo telefono'],
      'pt': ['Só', 'valor', 'comerciante', 'data', 'app', 'saem do teu telemóvel'],
    };
    for (final locale in _locales) {
      final disclosure = _arb(locale)['autoCaptureHowDisclosure'] as String;
      for (final word in sent[locale]!) {
        expect(disclosure, contains(word), reason: '$locale: $word');
      }
    }
  });

  test('the notice declares its placeholders', () {
    final meta = _arb('es')['@autoCaptureHowNotice'] as Map<String, dynamic>;
    expect((meta['placeholders'] as Map).keys.toSet(), {'amount', 'merchant', 'category'});
  });
}
