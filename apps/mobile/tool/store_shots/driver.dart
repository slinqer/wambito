// `flutter drive` host side of tool/store_shots/shots_test.dart: writes each screenshot the app takes
// to $SHOTS_OUT/<name>.png.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final out = Platform.environment['SHOTS_OUT'] ?? 'build/store_shots';
    final file = File('$out/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return true;
  },
);
