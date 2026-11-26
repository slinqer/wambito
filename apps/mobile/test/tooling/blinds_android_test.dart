// The widget's eye plays the blinds natively (haptics/Blinds.kt): the same numbers as Dart's.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback_event.dart';

void main() {
  final source = File('android/app/src/main/kotlin/com/wambito/app/haptics/Blinds.kt')
      .readAsStringSync();

  String kotlinOf(HapticPattern pattern) =>
      'HapticSpec(listOf(${pattern.waveform.map((ms) => '${ms}L').join(', ')}), listOf(' +
      pattern.primitives
          .map((s) => 'PrimitiveStep("${s.name}", ${s.scale}f, ${s.delayMs})')
          .join(', ') +
      '))';

  test('Blinds.kt plays the patterns Dart plays', () {
    expect(
      source,
      contains('val HIDDEN = ${kotlinOf(hapticPatterns[FeedbackEvent.amountsHidden]!)}'),
    );
    expect(
      source,
      contains('val SHOWN = ${kotlinOf(hapticPatterns[FeedbackEvent.amountsShown]!)}'),
    );
  });
}
