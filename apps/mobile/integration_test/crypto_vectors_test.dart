import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/crypto/vector_cases.dart';

/// The shared crypto vectors on a device, with the native implementation. The vectors come from
/// `--dart-define=WAMBITO_VECTORS=<base64 of packages/crypto/test-vectors.json>` (see
/// `scripts/run-native-vectors.sh`); they are never copied into the repo.
const _vectorsB64 = String.fromEnvironment('WAMBITO_VECTORS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (_vectorsB64.isEmpty) {
    throw StateError('WAMBITO_VECTORS not set');
  }

  test('runs on the native cryptography, not the Dart fallback', () {
    expect(Cryptography.instance.runtimeType.toString(), contains('Flutter'));
  });

  defineVectorTests(jsonDecode(utf8.decode(base64Decode(_vectorsB64))) as Map<String, Object?>);
}
