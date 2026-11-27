package com.wambito.app.haptics

/**
 * The blinds of the hide-amounts eye (lib/feedback/feedback_event.dart's `amountsHidden` and
 * `amountsShown`), for the widget's eye, which plays them without the app;
 * test/tooling/blinds_android_test.dart keeps the numbers equal to Dart's.
 */
object Blinds {
    // The blind comes down and shuts: two light ticks gaining weight, then a dull knock.
    val HIDDEN = HapticSpec(listOf(6L, 25L, 8L, 35L, 22L), listOf(PrimitiveStep("tick", 0.4f, 0), PrimitiveStep("tick", 0.6f, 25), PrimitiveStep("thud", 0.9f, 35)))

    // The blind goes up: a soft low knock, then lighter and lighter, nothing final.
    val SHOWN = HapticSpec(listOf(16L, 35L, 8L, 25L, 6L), listOf(PrimitiveStep("lowTick", 0.6f, 0), PrimitiveStep("tick", 0.5f, 35), PrimitiveStep("tick", 0.3f, 25)))
}
