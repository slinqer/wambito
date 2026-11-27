import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The widget's ＋ and 🎤 draw the app's own icons (spec "Widget buttons like the app's"): each vector
// drawable is a copy of its icon in docs/design/system/project/icons/icons.json, on the same 48 grid,
// with the same strokes (round caps and joins, as LkIcon draws them) and fills, in white for the tint.

const _drawables = 'android/app/src/main/res/drawable';

List<Map<String, dynamic>> _icon(String name) {
  final json =
      jsonDecode(File('../../docs/design/system/project/icons/icons.json').readAsStringSync())
          as Map<String, dynamic>;
  final icons = (json['icons'] ?? json) as Map<String, dynamic>;
  final entry = icons[name] as Map<String, dynamic>;
  return (entry['filled'] as List).cast<Map<String, dynamic>>();
}

/// The `<path>` elements of a vector drawable, as attribute maps.
List<Map<String, String>> _paths(String file) {
  final xml = File('$_drawables/$file').readAsStringSync();
  return [
    for (final m in RegExp(r'<path\b([^>]*)/>').allMatches(xml))
      {
        for (final a in RegExp(r'android:(\w+)="([^"]*)"').allMatches(m.group(1)!))
          a.group(1)!: a.group(2)!,
      },
  ];
}

void main() {
  for (final (file, icon) in [('ic_widget_add.xml', 'plus'), ('ic_widget_mic.xml', 'mic')]) {
    test('$file is icons.json\'s "$icon"', () {
      final xml = File('$_drawables/$file').readAsStringSync();
      expect(xml, contains('android:viewportWidth="48"'));
      expect(xml, contains('android:viewportHeight="48"'));
      final shapes = _icon(icon);
      final paths = _paths(file);
      expect(paths, hasLength(shapes.length));
      for (var i = 0; i < shapes.length; i++) {
        final shape = shapes[i];
        final path = paths[i];
        expect(path['pathData'], shape['d'], reason: '$file path $i');
        if (shape['fill'] == true) {
          expect(path['fillColor'], '#FFFFFFFF', reason: '$file path $i is filled');
          expect(path.containsKey('strokeWidth'), isFalse);
        } else {
          expect(path['strokeColor'], '#FFFFFFFF', reason: '$file path $i is stroked');
          expect(double.parse(path['strokeWidth']!), (shape['stroke'] as num).toDouble());
          expect(path['strokeLineCap'], 'round');
          expect(path['strokeLineJoin'], 'round');
        }
      }
    });
  }
}
