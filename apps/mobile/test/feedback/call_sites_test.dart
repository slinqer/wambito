// Where the app gives feedback: the swipes, the keypad, the add sheet and quick capture, with the
// phone's motor and speaker recorded.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/add/add_repository.dart';
import 'package:wambito/capture/capture_repository.dart';
import 'package:wambito/capture/engine/speech_engine.dart';
import 'package:wambito/capture/models_download.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/home/home_repository.dart' show HomeFailure;
import 'package:wambito/home/wambi_face.dart';
import 'package:wambito/ui/press_button.dart';

import '../add/fakes.dart';
import '../capture/fakes.dart';
import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../home/home_harness.dart';
import 'fakes.dart';

class _Env {
  _Env(this.server, this.platform, this.harness);
  final FakeHomeRepository server;
  final FakeFeedbackPlatform platform;
  final HomeHarness harness;

  List<List<int>> get waveforms => [for (final p in platform.haptics) p.waveform];

  /// The haptics of what happened (a save, a limit, Deshacer), without the touch of the bar's
  /// buttons and the sheets' landing and shutting around them.
  List<List<int>> get outcomes => [
    for (final p in platform.haptics)
      if (!_touches.contains(p)) p.waveform,
  ];

  static final _touches = {
    for (final event in [
      FeedbackEvent.addPressed,
      FeedbackEvent.addReleased,
      FeedbackEvent.micPressed,
      FeedbackEvent.micReleased,
      FeedbackEvent.sheetOpened,
      FeedbackEvent.sheetClosed,
    ])
      hapticPatterns[event]!,
  };

  /// The pattern of [event], as the platform got it.
  static HapticPattern of(FeedbackEvent event) => hapticPatterns[event]!;
}

Future<_Env> _pump(
  WidgetTester tester, {
  FakeHomeRepository? server,
  bool withAdd = false,
  bool withCapture = false,
  Size size = const Size(390, 844),
}) async {
  final repo =
      server ??
      (monthWithBudgets()..categoryList.addAll([category('cat-food', 'Comida', icon: '🍽️')]));
  final platform = FakeFeedbackPlatform();
  final harness = await pumpHome(
    tester,
    repo,
    size: size,
    overrides: [
      feedbackPlatformProvider.overrideWithValue(platform),
      soundSettingStoreProvider.overrideWithValue(FakeSoundStore()),
      vibrationSettingStoreProvider.overrideWithValue(FakeSoundStore()),
      if (withAdd) addRepositoryProvider.overrideWithValue(FakeAddRepository(repo)),
      if (withCapture) ...[
        captureRepositoryProvider.overrideWithValue(FakeCaptureRepository(repo)),
        speechEngineProvider.overrideWithValue(
          FakeSpeechEngine(
            transcripts: [
              ['gasté 15 mil en almuerzo'],
            ],
          ),
        ),
        modelStoreProvider.overrideWithValue(FakeModelStore()),
      ],
    ],
  );
  // The app builds feedback at its start (WambitoApp) and the setting is read back.
  harness.container.read(feedbackProvider);
  await tester.pump(Duration.zero);
  return _Env(repo, platform, harness);
}

/// A swipe: the finger down on [row], moved by [dx] over [ms] (a flick is fast).
Future<void> swipe(WidgetTester tester, Finder row, double dx, {int ms = 300}) async {
  await tester.timedDrag(row, Offset(dx, 0), Duration(milliseconds: ms));
  await tester.pumpAndSettle();
}

Future<void> _endTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 12));
  await tester.pumpAndSettle();
}

Future<void> saveBatchOf(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home.capture')));
  await tester.pumpAndSettle();
  final pick = find.byKey(const Key('capture.card.0.pick'));
  if (pick.evaluate().isNotEmpty) {
    await tester.tap(pick);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('capture.card.0.category.cat-food')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('capture.save')));
  // Not settled: the celebration lasts 2.5 s, the toast 8.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

WambiMood _mood(WidgetTester tester) => tester.widget<WambiFace>(find.byType(WambiFace)).mood;

void main() {
  group('swipes', () {
    testWidgets('a delete ticks at the threshold, then feels deleted; Deshacer feels undone', (
      tester,
    ) async {
      final env = await _pump(tester);
      await swipe(tester, find.text('Café'), -250);
      expect(env.waveforms, isEmpty, reason: 'a left swipe only opens Borrar: no tick, no delete');
      await tester.tap(find.text('BORRAR'));
      await tester.pumpAndSettle();
      expect(env.waveforms, [
        [14, 30, 8],
      ]);
      expect(env.platform.sounds, isEmpty, reason: 'gestures only vibrate');

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(env.waveforms.last, [8]);
      expect(env.platform.sounds, [FeedbackSound.undo]);
      await _endTimers(tester);
    });

    testWidgets('a delete the server refuses still felt like a delete, but has no undo', (
      tester,
    ) async {
      final repo = monthWithBudgets();
      repo.failures['delete'] = const HomeFailure(500);
      final env = await _pump(tester, server: repo);
      await swipe(tester, find.text('Café'), -250);
      await tester.tap(find.text('BORRAR'));
      await tester.pumpAndSettle();
      expect(env.waveforms, contains(equals([14, 30, 8])));
      expect(env.platform.sounds, isEmpty);
      await _endTimers(tester);
    });

    testWidgets('paying a pending row plays the paid sound and haptic', (tester) async {
      final env = await _pump(tester, size: tallPhone);
      await swipe(tester, find.text('Arriendo'), 250);
      expect(env.platform.sounds, [FeedbackSound.paid]);
      expect(env.waveforms.last, [10, 30, 10, 30, 24]);
      await _endTimers(tester);
    });

    testWidgets('a payment the server refuses is not celebrated', (tester) async {
      final repo = monthWithBudgets();
      repo.failures['markPaid'] = const HomeFailure(0);
      final env = await _pump(tester, server: repo);
      await swipe(tester, find.text('Arriendo'), 250);
      expect(env.platform.sounds, isEmpty);
      expect(env.waveforms, isNot(contains(equals([10, 30, 10, 30, 24]))));
      await _endTimers(tester);
    });

    testWidgets('the left side never ticks; the right one ticks each way it crosses the line', (
      tester,
    ) async {
      final env = await _pump(tester, size: tallPhone);
      final left = await tester.startGesture(tester.getCenter(find.text('Café')));
      await left.moveBy(const Offset(-230, 0));
      await tester.pump();
      expect(env.waveforms, isEmpty, reason: 'Borrar is never armed by a swipe');
      await left.up();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(find.text('Arriendo')));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(env.waveforms, isEmpty, reason: 'not yet at the line');
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(env.waveforms, [
        [10],
      ]);
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      expect(env.waveforms, [
        [10],
        [10],
      ]);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('the add sheet', () {
    testWidgets('a key press is a haptic tick through feedback, not the framework\'s', (
      tester,
    ) async {
      final env = await _pump(tester, withAdd: true);
      final framework = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        framework.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pumpAndSettle();
      env.platform.haptics.clear();
      await tester.tap(find.byKey(const Key('keypad.5')));
      await tester.pump();
      expect(env.platform.haptics, [_Env.of(FeedbackEvent.keyPressed)]);
      expect(env.platform.sounds, isEmpty);
      expect(framework, isNot(contains('HapticFeedback.vibrate')));
    });

    testWidgets('saving plays the saved sound and haptic; Deshacer the undo ones', (tester) async {
      final env = await _pump(tester, withAdd: true);
      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('keypad.5')));
      await tester.pump();
      env.platform.haptics.clear();
      await tester.tap(find.byKey(const Key('add.save')));
      await tester.pumpAndSettle();
      expect(env.platform.sounds, [FeedbackSound.expenseSaved]);
      // The save's own feel, then the sheet shutting as it slides away.
      expect(env.platform.haptics, [
        _Env.of(FeedbackEvent.saved),
        _Env.of(FeedbackEvent.sheetClosed),
      ]);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(env.platform.sounds, [FeedbackSound.expenseSaved, FeedbackSound.undo]);
      expect(env.waveforms.last, [8]);
      await _endTimers(tester);
    });

    testWidgets('muted, a save still vibrates and plays nothing', (tester) async {
      final env = await _pump(tester, withAdd: true);
      await env.harness.container.read(soundEnabledProvider.notifier).set(false);
      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('keypad.5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add.save')));
      await tester.pumpAndSettle();
      expect(env.platform.sounds, isEmpty);
      expect(env.waveforms, contains(equals([12, 40, 18])));
      await _endTimers(tester);
    });
  });

  group('the bar\'s buttons and the sheets feel like real objects', () {
    testWidgets('the ＋ clicks down as the finger lands and back up as it lets go', (tester) async {
      final env = await _pump(tester, withAdd: true);
      final finger = await tester.startGesture(tester.getCenter(find.byKey(const Key('home.add'))));
      await tester.pump();
      expect(env.platform.haptics, [
        _Env.of(FeedbackEvent.addPressed),
      ], reason: 'before letting go');
      await finger.up();
      await tester.pump();
      expect(env.platform.haptics, [
        _Env.of(FeedbackEvent.addPressed),
        _Env.of(FeedbackEvent.addReleased),
      ]);
      await tester.pumpAndSettle();
    });

    testWidgets('the 🎤 clicks the same way, softer', (tester) async {
      final env = await _pump(tester, withCapture: true);
      final finger = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('home.capture'))),
      );
      await tester.pump();
      expect(env.platform.haptics, [_Env.of(FeedbackEvent.micPressed)]);
      await finger.up();
      await tester.pump();
      expect(env.platform.haptics.last, _Env.of(FeedbackEvent.micReleased));
      await tester.pumpAndSettle();
      await _endTimers(tester);
    });

    testWidgets('a sheet lands once it is all the way up, and shuts once it is all the way out', (
      tester,
    ) async {
      final env = await _pump(tester, withAdd: true);
      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(env.platform.haptics, isNot(contains(_Env.of(FeedbackEvent.sheetOpened))));
      await tester.pumpAndSettle();
      expect(env.platform.haptics.last, _Env.of(FeedbackEvent.sheetOpened));

      env.platform.haptics.clear();
      await tester.tap(find.text('CERRAR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(env.platform.haptics, isEmpty, reason: 'still sliding out');
      await tester.pumpAndSettle();
      expect(env.platform.haptics, [_Env.of(FeedbackEvent.sheetClosed)]);
    });

    testWidgets('the backspace held down clears the amount with a firmer feel', (tester) async {
      final env = await _pump(tester, withAdd: true);
      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pumpAndSettle();
      for (final key in ['5', '6']) {
        await tester.tap(find.byKey(Key('keypad.$key')));
        await tester.pump();
      }
      env.platform.haptics.clear();
      await tester.longPress(find.byKey(const Key('keypad.backspace')));
      await tester.pumpAndSettle();
      expect(env.platform.haptics, [_Env.of(FeedbackEvent.amountCleared)]);
      // Nothing left to save.
      expect(tester.widget<PressButton>(find.byKey(const Key('add.save'))).onPressed, isNull);
    });
  });

  group('quick capture', () {
    testWidgets('a batch save celebrates: the sound, the haptic and Wambi', (tester) async {
      final env = await _pump(tester, withCapture: true);
      expect(_mood(tester), isNot(WambiMood.celebrating));
      await saveBatchOf(tester);
      expect(env.platform.sounds, [FeedbackSound.expenseSaved]);
      expect(env.outcomes, [
        [12, 40, 18],
      ]);
      expect(_mood(tester), WambiMood.celebrating);

      // He rests again after the celebration, like for any save.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_mood(tester), isNot(WambiMood.celebrating));
      await _endTimers(tester);
    });

    testWidgets('the batch\'s Deshacer feels undone', (tester) async {
      final env = await _pump(tester, withCapture: true);
      await saveBatchOf(tester);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(env.platform.sounds, [FeedbackSound.expenseSaved, FeedbackSound.undo]);
      expect(env.waveforms.last, [8]);
      await _endTimers(tester);
    });
  });

  group('the saved feedback follows the kind and the limit state, like the web', () {
    Future<void> addExpense(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('keypad.5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add.save')));
      await tester.pumpAndSettle();
    }

    FakeHomeRepository server(String state) => monthWithBudgets()
      ..categoryList.add(category('cat-food', 'Comida', icon: '🍽️'))
      ..categoryLines = [
        for (final id in ['cat-groceries', 'cat-food'])
          categorySummary(id, budget: 100000, spent: 90000, state: state),
      ];

    testWidgets('an expense within its limit is the plain saved sound', (tester) async {
      final env = await _pump(tester, server: server('ok'), withAdd: true);
      await addExpense(tester);
      expect(env.platform.sounds, [FeedbackSound.expenseSaved]);
      await _endTimers(tester);
    });

    testWidgets('an expense that leaves its category near its limit plays the near-limit ones', (
      tester,
    ) async {
      final env = await _pump(tester, server: server('near'), withAdd: true);
      await addExpense(tester);
      expect(env.platform.sounds, [FeedbackSound.nearLimit]);
      expect(env.outcomes.last, [30]);
      await _endTimers(tester);
    });

    testWidgets('an expense that leaves its category over its limit plays the over-budget ones', (
      tester,
    ) async {
      final env = await _pump(tester, server: server('over'), withAdd: true);
      await addExpense(tester);
      expect(env.platform.sounds, [FeedbackSound.overBudget]);
      expect(env.outcomes.last, [40, 60, 40]);
      await _endTimers(tester);
    });

    testWidgets('an income plays the income sound', (tester) async {
      final repo = monthWithBudgets()
        ..categoryList.addAll([category('cat-pay', 'Sueldo', kind: 'income')]);
      final env = await _pump(tester, server: repo, withAdd: true);
      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add.kind.income')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('keypad.5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add.save')));
      await tester.pumpAndSettle();
      expect(env.platform.sounds, [FeedbackSound.incomeSaved]);
      await _endTimers(tester);
    });

    testWidgets('a slow summary does not hold the feel back for more than two seconds', (
      tester,
    ) async {
      final repo = server('over');
      final env = await _pump(tester, server: repo, withAdd: true);
      repo.holdSummary = Completer<void>();
      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('keypad.5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add.save')));
      await tester.pump(const Duration(seconds: 1));
      expect(env.platform.sounds, isEmpty, reason: 'still waiting for the figures');
      await tester.pump(const Duration(seconds: 2));
      expect(env.platform.sounds, hasLength(1), reason: 'then it goes with what it has');
      repo.holdSummary!.complete();
      await _endTimers(tester);
    });

    testWidgets('a batch takes the state after the whole batch, and does not celebrate over', (
      tester,
    ) async {
      final env = await _pump(tester, server: server('over'), withCapture: true);
      await saveBatchOf(tester);
      expect(env.platform.sounds, [FeedbackSound.overBudget]);
      expect(env.outcomes, [
        [40, 60, 40],
      ]);
      expect(_mood(tester), isNot(WambiMood.celebrating), reason: 'no party over the limit');
      await _endTimers(tester);
    });

    testWidgets('a batch near the limit warns too, with no party', (tester) async {
      final env = await _pump(tester, server: server('near'), withCapture: true);
      await saveBatchOf(tester);
      expect(env.platform.sounds, [FeedbackSound.nearLimit]);
      expect(_mood(tester), isNot(WambiMood.celebrating));
      await _endTimers(tester);
    });
  });
}
