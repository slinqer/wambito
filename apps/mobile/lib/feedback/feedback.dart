import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'celebration.dart';
import 'feedback_event.dart';
import 'feedback_platform.dart';
import 'sound_setting.dart';
import 'vibration_setting.dart';

export 'celebration.dart' show celebratedEvents;
export 'feedback_event.dart';
export 'feedback_platform.dart';
export 'sound_setting.dart';
export 'vibration_setting.dart';

/// Gives feedback for something that happened (spec section 6.2): plays its sound (unless muted),
/// vibrates (unless vibration is off) and, for a save or a payment, celebrates (`CelebrationHost`).
/// Each waits for its setting to be read and stays quiet when it is off. It never throws: a phone
/// with no motor or speaker just skips that part. Call it from a gesture's handler:
/// `ref.read(feedbackProvider)(FeedbackEvent.saved)`, or [FeedbackContext.feedback] where there is
/// only a `BuildContext`.
final feedbackProvider = Provider<void Function(FeedbackEvent event)>((ref) {
  final platform = ref.watch(feedbackPlatformProvider);
  // Starts reading both settings now, at the app's start: nothing plays or vibrates before they
  // are known.
  ref.read(soundEnabledProvider);
  ref.read(vibrationEnabledProvider);
  _quietly(platform.warmUp);

  void run(FeedbackEvent event) {
    // The party is the person's to see whatever the sound and the motor are set to: the web's
    // `Celebration` listens to `feedback()` itself.
    if (celebratedEvents.contains(event)) ref.read(celebrationBurstsProvider.notifier).burst();
    final pattern = hapticPatterns[event];
    if (pattern != null && _vibrationOn(ref)) _quietly(() => platform.vibrate(pattern));
    final sound = feedbackSounds[event];
    if (sound != null && _soundOn(ref)) _quietly(() => platform.play(sound));
  }

  return run;
});

/// Plays [pattern] on the motor, for a feel that is not one fixed event (the swipe's notches, whose
/// tick grows with the distance). Quiet while the vibration setting is off or not yet known.
final hapticProvider = Provider<void Function(HapticPattern pattern)>((ref) {
  final platform = ref.watch(feedbackPlatformProvider);
  ref.read(vibrationEnabledProvider);
  return (pattern) {
    if (_vibrationOn(ref)) _quietly(() => platform.vibrate(pattern));
  };
});

bool _soundOn(Ref ref) {
  try {
    return ref.read(soundEnabledProvider.notifier).playable;
  } on Object {
    return false;
  }
}

bool _vibrationOn(Ref ref) {
  try {
    return ref.read(vibrationEnabledProvider.notifier).vibratable;
  } on Object {
    return false;
  }
}

/// Runs [call] without waiting, and without letting it fail.
void _quietly(Future<void> Function() call) {
  try {
    unawaited(call().catchError((Object _) {}));
  } on Object {
    // Feedback is a nicety: one part failing must not stop the other or the caller.
  }
}

/// Counts the moments Wambi celebrates by himself, apart from a save or a payment he talks about
/// (home shows those through its own events): a batch from quick capture. Each is a new number, so
/// two in a row both count.
class Celebration extends Notifier<int> {
  @override
  int build() => 0;

  void celebrate() => state++;
}

final celebrationProvider = NotifierProvider<Celebration, int>(Celebration.new);

/// [feedbackProvider] as found from [context] now, for a widget that gives feedback after it may
/// have left the tree (a sheet that shuts as its route goes). Without a `ProviderScope` (a bare
/// widget test) it does nothing.
void Function(FeedbackEvent event) feedbackOf(BuildContext context) {
  try {
    final container = ProviderScope.containerOf(context, listen: false);
    return (event) => container.read(feedbackProvider)(event);
  } on Object {
    return (_) {};
  }
}

extension FeedbackContext on BuildContext {
  /// [hapticProvider] for a widget that is not a `ConsumerWidget`; nothing without a scope.
  void haptic(HapticPattern pattern) {
    try {
      ProviderScope.containerOf(this, listen: false).read(hapticProvider)(pattern);
    } on Object {
      // No scope: no feel.
    }
  }

  /// [feedbackProvider] for a widget that is not a `ConsumerWidget`. Without a `ProviderScope`
  /// (a bare widget test) it does nothing.
  void feedback(FeedbackEvent event) {
    try {
      ProviderScope.containerOf(this, listen: false).read(feedbackProvider)(event);
    } on Object {
      // No scope: no feedback.
    }
  }
}
