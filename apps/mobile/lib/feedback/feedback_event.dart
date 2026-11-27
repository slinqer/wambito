/// What just happened, as the person feels it (the web's `FeedbackEvent`, apps/web/app/feedback).
enum FeedbackEvent {
  /// An expense, or a batch, was saved (the web's `expenseSaved`).
  saved,

  /// An income, or a batch of incomes, was saved.
  incomeSaved,

  /// A save left its category near its limit: it says so instead of celebrating.
  nearLimit,

  /// A save left its category over its limit: it says so instead of celebrating.
  overBudget,

  /// A pending movement was marked paid.
  paid,

  /// A movement was deleted (a swipe).
  deleted,

  /// Deshacer took a save or a delete back.
  undo,

  /// A swiped row crossed the line where letting go runs its action (or came back under it).
  thresholdCrossed,

  /// A pager settled on the other page. The app has no pager yet (home is one list), so nothing
  /// fires it; it is here so the first pager has its feel ready.
  pageChanged,

  /// A key of the add sheet's keypad.
  keyPressed,

  /// The keypad's backspace, held down, cleared the whole amount.
  amountCleared,

  /// A finger came down on the ＋ of the bottom bar: it clicks down like a real button.
  addPressed,

  /// The finger left the ＋: it springs back up, lighter than the press.
  addReleased,

  /// A finger came down on the 🎤: the ＋'s click, softer (it is the smaller button).
  micPressed,

  /// The finger left the 🎤.
  micReleased,

  /// A sheet slid all the way up and came to rest: it lands, with its weight.
  sheetOpened,

  /// A sheet slid all the way down and out: it shuts, like a drawer pushed home.
  sheetClosed,

  /// Análisis's charts swept into figures (the first ones, or another period's, month's or kind's):
  /// a wheel spinning down, one tick per notch as it slows, and a click as it stops where the
  /// figures settle.
  wheelSpun,

  /// Home's eye (or the widget's) closed: the blind comes down and shuts.
  amountsHidden,

  /// The eye opened again: the blind goes up.
  amountsShown,
}

/// One step of the Android haptic composition: a `PRIMITIVE_CLICK`, `PRIMITIVE_TICK`,
/// `PRIMITIVE_THUD` or `PRIMITIVE_LOW_TICK` at a [scale] (0 to 1) after [delayMs] of quiet.
class HapticPrimitive {
  const HapticPrimitive(this.name, this.scale, {this.delayMs = 0});

  /// `click` or `tick`, which every phone with primitives has (Android 11, API 30), or `thud` or
  /// `lowTick` (Android 12): the deep knock of something heavy. A motor without those two plays a
  /// `click` or a `tick` in their place (HapticsChannel.kt).
  final String name;
  final double scale;
  final int delayMs;

  Map<String, Object> toJson() => {'name': name, 'scale': scale, 'delay': delayMs};
}

/// How an event feels: [waveform] is the web's pattern in ms (vibrate, pause, vibrate...), which
/// phones without composition primitives play; [primitives] is the same feel as a composition for
/// Android 11 and up (HapticsChannel.kt picks, by asking the motor what it supports).
class HapticPattern {
  const HapticPattern(this.waveform, this.primitives);

  final List<int> waveform;
  final List<HapticPrimitive> primitives;

  Map<String, Object> toJson() => {
    'waveform': waveform,
    'primitives': [for (final step in primitives) step.toJson()],
  };
}

/// The web's vibration patterns, one for one, with a composition of the same shape. Gestures are
/// one short tick each, light enough to repeat while a finger moves.
const hapticPatterns = <FeedbackEvent, HapticPattern>{
  FeedbackEvent.saved: HapticPattern(
    [12, 40, 18],
    [HapticPrimitive('tick', 0.6), HapticPrimitive('click', 1, delayMs: 40)],
  ),
  FeedbackEvent.incomeSaved: HapticPattern(
    [12, 40, 18],
    [HapticPrimitive('tick', 0.6), HapticPrimitive('click', 1, delayMs: 40)],
  ),
  FeedbackEvent.nearLimit: HapticPattern([30], [HapticPrimitive('click', 0.6)]),
  FeedbackEvent.overBudget: HapticPattern(
    [40, 60, 40],
    [HapticPrimitive('click', 1), HapticPrimitive('click', 1, delayMs: 60)],
  ),
  FeedbackEvent.paid: HapticPattern(
    [10, 30, 10, 30, 24],
    [
      HapticPrimitive('tick', 0.5),
      HapticPrimitive('tick', 0.7, delayMs: 30),
      HapticPrimitive('click', 1, delayMs: 30),
    ],
  ),
  FeedbackEvent.deleted: HapticPattern(
    [14, 30, 8],
    [HapticPrimitive('click', 0.8), HapticPrimitive('tick', 0.5, delayMs: 30)],
  ),
  FeedbackEvent.undo: HapticPattern([8], [HapticPrimitive('tick', 0.5)]),
  FeedbackEvent.thresholdCrossed: HapticPattern([10], [HapticPrimitive('tick', 0.7)]),
  FeedbackEvent.pageChanged: HapticPattern([15], [HapticPrimitive('tick', 1)]),
  // A key is a firm little click, under the ＋'s: it is felt on every digit.
  FeedbackEvent.keyPressed: HapticPattern([14], [HapticPrimitive('click', 0.7)]),
  // Everything typed goes at once: a full click and a tick after it, like a reset.
  FeedbackEvent.amountCleared: HapticPattern(
    [20, 40, 10],
    [HapticPrimitive('click', 1), HapticPrimitive('tick', 0.6, delayMs: 40)],
  ),
  // A physical button: a firm click going down and a lighter one coming back up. The ＋ is the
  // bar's main button, so it clicks harder than the 🎤 both ways.
  FeedbackEvent.addPressed: HapticPattern([20], [HapticPrimitive('click', 1)]),
  FeedbackEvent.addReleased: HapticPattern([10], [HapticPrimitive('tick', 0.7)]),
  FeedbackEvent.micPressed: HapticPattern([12], [HapticPrimitive('click', 0.55)]),
  FeedbackEvent.micReleased: HapticPattern([6], [HapticPrimitive('tick', 0.4)]),
  // A sheet as a real object: it lands with a low knock and a small settle; it shuts with one
  // short knock, lighter, as it slides out of sight.
  FeedbackEvent.sheetOpened: HapticPattern(
    [18, 50, 6],
    [HapticPrimitive('thud', 0.7), HapticPrimitive('lowTick', 0.35, delayMs: 50)],
  ),
  FeedbackEvent.sheetClosed: HapticPattern([16], [HapticPrimitive('thud', 0.5)]),
  // The charts' sweep (`durationHop`, 520 ms, easeOut) as a wheel with 12 notches: a tick as it
  // starts and as each notch passes, further apart as it slows (the times easeOut crosses each
  // twelfth), and a full click where it stops. Each pause is the gap after an 8 ms tick; the ticks
  // are firm (it is a heavy wheel) and soften a little as it slows.
  // The blind comes down and shuts: two light ticks gaining weight, then a dull knock.
  FeedbackEvent.amountsHidden: HapticPattern(
    [6, 25, 8, 35, 22],
    [
      HapticPrimitive('tick', 0.4),
      HapticPrimitive('tick', 0.6, delayMs: 25),
      HapticPrimitive('thud', 0.9, delayMs: 35),
    ],
  ),
  // The blind goes up, the mirror: a soft low knock, then lighter and lighter, nothing final.
  FeedbackEvent.amountsShown: HapticPattern(
    [16, 35, 8, 25, 6],
    [
      HapticPrimitive('lowTick', 0.6),
      HapticPrimitive('tick', 0.5, delayMs: 35),
      HapticPrimitive('tick', 0.3, delayMs: 25),
    ],
  ),
  FeedbackEvent.wheelSpun: HapticPattern(
    [8, 18, 8, 20, 8, 21, 8, 22, 8, 24, 8, 25, 8, 27, 8, 30, 8, 34, 8, 39, 8, 50, 8, 114, 20],
    [
      HapticPrimitive('tick', 0.85),
      HapticPrimitive('tick', 0.85, delayMs: 18),
      HapticPrimitive('tick', 0.85, delayMs: 20),
      HapticPrimitive('tick', 0.8, delayMs: 21),
      HapticPrimitive('tick', 0.8, delayMs: 22),
      HapticPrimitive('tick', 0.8, delayMs: 24),
      HapticPrimitive('tick', 0.75, delayMs: 25),
      HapticPrimitive('tick', 0.75, delayMs: 27),
      HapticPrimitive('tick', 0.75, delayMs: 30),
      HapticPrimitive('tick', 0.7, delayMs: 34),
      HapticPrimitive('tick', 0.7, delayMs: 39),
      HapticPrimitive('tick', 0.65, delayMs: 50),
      HapticPrimitive('click', 1, delayMs: 114),
    ],
  ),
};

/// The web's sound files (assets/sounds, with the licence note in its README).
enum FeedbackSound {
  expenseSaved('assets/sounds/expense-saved.mp3'),
  incomeSaved('assets/sounds/income-saved.mp3'),
  nearLimit('assets/sounds/near-limit.mp3'),
  overBudget('assets/sounds/over-budget.mp3'),
  paid('assets/sounds/paid.mp3'),
  undo('assets/sounds/undo.mp3');

  const FeedbackSound(this.asset);

  final String asset;
}

/// The sound of an event. Gestures (a threshold, a page, a delete, a key) only vibrate: a sound on
/// every swipe or key would wear thin fast (the web's rule).
const feedbackSounds = <FeedbackEvent, FeedbackSound>{
  FeedbackEvent.saved: FeedbackSound.expenseSaved,
  FeedbackEvent.incomeSaved: FeedbackSound.incomeSaved,
  FeedbackEvent.nearLimit: FeedbackSound.nearLimit,
  FeedbackEvent.overBudget: FeedbackSound.overBudget,
  FeedbackEvent.paid: FeedbackSound.paid,
  FeedbackEvent.undo: FeedbackSound.undo,
};
