import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/lk_icon_shapes.dart';
import 'package:wambito/ui/lk_icons.dart';

/// The icons both apps draw: the web reads this file, the phone a copy of it in Dart.
const _source = '../../docs/design/system/project/icons/icons.json';

void main() {
  test('the Dart copy of the icons equals the shared icons.json', () {
    final json = jsonDecode(File(_source).readAsStringSync()) as Map<String, dynamic>;
    final icons = json['icons'] as Map<String, dynamic>;
    expect(lkIconShapes.keys.toSet(), icons.keys.map(LkIconName.fromId).toSet());
    for (final MapEntry(key: id, value: variants) in icons.entries) {
      final name = LkIconName.fromId(id);
      for (final MapEntry(key: variant, value: shapes)
          in (variants as Map<String, dynamic>).entries) {
        final mine =
            lkIconShapes[name]![variant == 'outline'
                ? LkIconVariant.outline
                : LkIconVariant.filled]!;
        expect(mine.length, (shapes as List).length, reason: '$id $variant');
        for (var i = 0; i < mine.length; i++) {
          final shape = shapes[i] as Map<String, dynamic>;
          expect(mine[i].d, shape['d'], reason: '$id $variant $i');
          expect(mine[i].fill, shape['fill'] == true, reason: '$id $variant $i');
          expect(mine[i].evenOdd, shape['evenOdd'] == true, reason: '$id $variant $i');
          expect(
            mine[i].stroke,
            (shape['stroke'] as num?)?.toDouble() ?? 0,
            reason: '$id $variant $i',
          );
        }
      }
    }
  });

  test('an icon drawn once has the same shapes outlined', () {
    expect(
      shapesOf(LkIconName.search, LkIconVariant.outline),
      shapesOf(LkIconName.search, LkIconVariant.filled),
    );
    expect(
      shapesOf(LkIconName.home, LkIconVariant.outline),
      isNot(shapesOf(LkIconName.home, LkIconVariant.filled)),
    );
  });

  testWidgets('LkIcon paints at its size, hidden from semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: LkIcon(LkIconName.home, size: 26, color: Color(0xFFFFFFFF))),
      ),
    );
    expect(tester.getSize(find.byType(LkIcon)), const Size.square(26));
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
    semantics.dispose();
  });
}
