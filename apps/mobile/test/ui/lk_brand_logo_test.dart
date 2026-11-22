import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/lk_brand_logo.dart';
import 'package:wambito/ui/svg_path.dart';

/// The logos both apps draw: the web reads this file, the phone a copy of it in Dart.
const _source = '../../docs/design/system/project/icons/brands.json';

void main() {
  test('the Dart copy of the brand logos equals the shared brands.json', () {
    final json = jsonDecode(File(_source).readAsStringSync()) as Map<String, dynamic>;
    final logos = json['logos'] as Map<String, dynamic>;
    expect(lkBrandLogos.keys.toSet(), logos.keys.map(LkBrand.fromId).toSet());
    expect(LkBrand.values.length, logos.length);
    for (final MapEntry(key: id, value: logo) in logos.entries) {
      final mine = lkBrandLogos[LkBrand.fromId(id)]!;
      final source = logo as Map<String, dynamic>;
      expect(mine.viewBox, source['viewBox'], reason: id);
      final paths = source['paths'] as List;
      expect(mine.paths.length, paths.length, reason: id);
      for (var i = 0; i < paths.length; i++) {
        final path = paths[i] as Map<String, dynamic>;
        expect(mine.paths[i].d, path['d'], reason: '$id $i');
        expect(mine.paths[i].evenOdd, path['evenOdd'] == true, reason: '$id $i');
      }
    }
  });

  test('every logo path parses and has a size', () {
    for (final brand in LkBrand.values) {
      final logo = lkBrandLogos[brand]!;
      expect(logo.viewBox.split(' ').length, 4, reason: brand.id);
      for (final path in logo.paths) {
        expect(parseSvgPath(path.d).getBounds().isEmpty, isFalse, reason: brand.id);
      }
    }
  });

  testWidgets('LkBrandLogo paints at its size, hidden from semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: LkBrandLogo(LkBrand.googleWallet, size: 30, color: Color(0xFFFFFFFF))),
      ),
    );
    expect(tester.getSize(find.byType(LkBrandLogo)), const Size.square(30));
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
    semantics.dispose();
  });

  test('the ids are the names of brands.json', () {
    expect(LkBrand.googleWallet.id, 'google-wallet');
    expect(LkBrand.fromId('chatgpt'), LkBrand.chatgpt);
  });
}
