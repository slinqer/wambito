import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/l10n/app_localizations.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

/// The message keys of an ARB catalog: everything but `@@locale` and `@key` metadata.
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((key) => !key.startsWith('@')).toSet();

/// The argument names an ICU message uses: `{name}`, and the `{count, plural, …}` and
/// `{x, select, …}` variables, at any depth. Branch bodies such as `=1{…}` are not arguments.
Set<String> _arguments(String message) => _read(message).names;

/// The branches of every plural and select in a message, as `count:plural:one|other`. A plural's
/// `=1` and `one` are the same branch. An explicit `=0` is not counted: bare `pt` calls 0 `one` in
/// Flutter's plural rules (it is Brazilian there), so Portuguese adds a `=0` that reads as `other`.
Set<String> _branches(String message) => _read(message).branches;

({Set<String> names, Set<String> branches}) _read(String message) {
  final names = <String>{};
  final branches = <String>{};
  var i = 0;

  void skipSpaces() {
    while (i < message.length && message[i].trim().isEmpty) {
      i++;
    }
  }

  String readUntil(Set<String> stops) {
    final start = i;
    while (i < message.length && !stops.contains(message[i])) {
      i++;
    }
    return message.substring(start, i).trim();
  }

  // Reads plain text and arguments until an unmatched `}` (or the end), which it leaves unread.
  void text() {
    while (i < message.length && message[i] != '}') {
      if (message[i] != '{') {
        i++;
        continue;
      }
      i++; // {
      final name = readUntil({',', '}'});
      names.add(name);
      if (i < message.length && message[i] == ',') {
        i++; // ,
        final type = readUntil({',', '}'});
        if ((type == 'plural' || type == 'select') && message[i] == ',') {
          i++; // ,
          skipSpaces();
          final selectors = <String>[];
          while (i < message.length && message[i] != '}') {
            final selector = readUntil({'{'}); // =0, one, other, a select value
            if (type == 'plural' && selector == '=0') {
              // Not a branch of its own; see above.
            } else {
              selectors.add(type == 'plural' && selector == '=1' ? 'one' : selector);
            }
            i++; // {
            text();
            i++; // }
            skipSpaces();
          }
          selectors.sort();
          branches.add('$name:$type:${selectors.join('|')}');
        }
      }
      i++; // } closing the argument
    }
  }

  text();
  return (names: names, branches: branches);
}

void main() {
  const languages = ['es', 'en', 'it', 'pt'];
  final arbs = {for (final language in languages) language: _arb(language)};
  final es = arbs['es']!;

  Set<String> declared(String key) =>
      ((es['@$key'] as Map<String, dynamic>?)?['placeholders'] as Map<String, dynamic>?)?.keys
          .toSet() ??
      <String>{};

  for (final language in languages.skip(1)) {
    test('ARB parity: es and $language have the same keys', () {
      expect(_messageKeys(arbs[language]!), _messageKeys(es));
    });

    test('ARB parity: es and $language have the same placeholders and plural branches', () {
      for (final key in _messageKeys(es)) {
        final message = arbs[language]![key] as String;
        expect(_arguments(message), declared(key), reason: '$language "$key" vs the es template');
        expect(
          _branches(message),
          _branches(es[key] as String),
          reason: '$language "$key" branches vs es',
        );
      }
    });

    test('ARB parity: $language has no empty messages', () {
      for (final key in _messageKeys(arbs[language]!)) {
        expect((arbs[language]![key] as String).trim(), isNotEmpty, reason: '$language "$key"');
      }
    });
  }

  test('ARB parity: es declares the placeholders its messages use', () {
    for (final key in _messageKeys(es)) {
      expect(_arguments(es[key] as String), declared(key), reason: 'es "$key" vs its @$key');
    }
  });

  test('the ICU argument reader ignores plural branch bodies', () {
    expect(
      _arguments('{count, plural, =0{Nada} =1{Uno en {category}} other{{count} en {category}}}'),
      {'count', 'category'},
    );
  });

  test('the branch reader sees nested plurals and treats =1 as one', () {
    expect(_branches('{n, plural, =1{a} other{b}}'), {'n:plural:one|other'});
    expect(_branches('{n, plural, =0{c} =1{a} other{c}}'), {'n:plural:one|other'});
    expect(_branches('{n, plural, one{a} other{b}}'), {'n:plural:one|other'});
    expect(_branches('x {a, plural, one{{b, select, m{1} other{2}}} other{3}}'), {
      'a:plural:one|other',
      'b:select:m|other',
    });
  });

  // The web's guard (apps/web/app/i18n/messages.test.ts), over the app's Portuguese.
  final brazilian = RegExp(
    r'(?<![\p{L}])(celular|tela|usuário|registrar|você|gastando|salvar|arquivo|deletar|baixar|aplicativo|cadastro|conta corrente|ônibus)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  );

  test('the Brazilian-word guard sees accented words and spares European ones', () {
    expect(brazilian.hasMatch('obrigado, você sabe'), isTrue);
    expect(brazilian.hasMatch('apanha o ônibus'), isTrue);
    expect(brazilian.hasMatch('o Usuário'), isTrue);
    expect(brazilian.hasMatch('o teu telemóvel'), isFalse);
  });

  test('app_pt.arb is European Portuguese: no Brazilian words', () {
    final pt = arbs['pt']!;
    for (final key in _messageKeys(pt)) {
      expect(pt[key] as String, isNot(matches(brazilian)), reason: 'pt "$key"');
    }
  });

  test('app_pt.arb says telemóvel for the phone, as the base and the web\'s pt do', () {
    final pt = arbs['pt']!;
    final word = RegExp(r'(?<![\p{L}])telefones?(?![\p{L}])', unicode: true, caseSensitive: false);
    for (final key in _messageKeys(pt)) {
      expect(pt[key] as String, isNot(matches(word)), reason: 'pt "$key"');
    }
  });

  test('Italian and Portuguese do not use the Colombian slang', () {
    final slang = RegExp(r'(?<![\p{L}])(lukas?|lucas|palos?)(?![\p{L}])', unicode: true);
    for (final language in ['it', 'pt']) {
      for (final key in _messageKeys(arbs[language]!)) {
        // A web address is not copy.
        final copy = (arbs[language]![key] as String).replaceAll(RegExp(r'https?://\S+'), '');
        expect(copy, isNot(matches(slang)), reason: '$language "$key"');
      }
    }
  });

  test('Portuguese plurals say =1 and =0, not one: bare pt counts 0 as one', () {
    final pt = arbs['pt']!;
    for (final key in _messageKeys(pt)) {
      final message = pt[key] as String;
      expect(message.contains(RegExp(r'plural,\s*one\s*\{|\sone\s*\{')), isFalse, reason: key);
      final plurals = RegExp(r'plural,').allMatches(message).length;
      expect('=1{'.allMatches(message).length, plurals, reason: 'pt "$key" has =1 in each plural');
      expect('=0{'.allMatches(message).length, plurals, reason: 'pt "$key" has =0 in each plural');
    }
  });

  testWidgets('plurals and placeholders render in all four languages', (tester) async {
    Future<AppLocalizations> load(String language) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        Localizations(
          locale: Locale(language),
          delegates: AppLocalizations.localizationsDelegates,
          child: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return l10n;
    }

    final es = await load('es');
    final en = await load('en');
    final it = await load('it');
    final pt = await load('pt');

    expect(es.appName, 'Wambito');
    expect(it.appName, 'Wambito');
    expect(pt.appName, 'Wambito');
    expect(es.savedMovements(1, 'Mercado'), 'Guardaste 1 movimiento en Mercado');
    expect(es.savedMovements(3, 'Mercado'), 'Guardaste 3 movimientos en Mercado');
    expect(en.savedMovements(1, 'Mercado'), 'You saved 1 movement in Mercado');
    expect(en.savedMovements(3, 'Mercado'), 'You saved 3 movements in Mercado');
    expect(it.savedMovements(1, 'Spesa'), contains('1 movimento'));
    expect(it.savedMovements(3, 'Spesa'), contains('3 movimenti'));
    expect(pt.savedMovements(1, 'Mercado'), contains('1 movimento'));
    expect(pt.savedMovements(3, 'Mercado'), contains('3 movimentos'));
    // Bare pt would call 0 "one": the =1 branches keep "0 movimentos".
    expect(pt.importConfirm(0), isNot(contains('0 movimento ')));
    expect(pt.importConfirm(0), endsWith('0 movimentos'));
    expect(pt.importConfirm(1), endsWith('1 movimento'));
    expect(it.importConfirm(2), endsWith('2 movimenti'));
  });
}
