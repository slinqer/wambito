import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'vector_cases.dart';

/// Loads the shared vectors by relative path and runs them on the host.
void main() {
  final vectors = jsonDecode(
    File('../../packages/crypto/test-vectors.json').readAsStringSync(),
  ) as Map<String, Object?>;
  defineVectorTests(vectors);
}
