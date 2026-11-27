import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/theme/tokens.g.dart';

import 'fakes.dart';

ProviderContainer containerWith(
  FakeFeedbackPlatform platform, {
  SoundSettingStore? store,
  FlagStore? vibrationStore,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      feedbackPlatformProvider.overrideWithValue(platform),
      soundSettingStoreProvider.overrideWithValue(store ?? FakeSoundStore()),
      vibrationSettingStoreProvider.overrideWithValue(vibrationStore ?? FakeSoundStore()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The app at rest: feedback is built (at the start, by the app) and the sound setting is read.
Future<void> started(ProviderContainer container) async {
  container.read(feedbackProvider);
  await container.read(soundEnabledProvider.notifier).ready;
  await container.read(vibrationEnabledProvider.notifier).ready;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the blinds are mirrors: down gains weight and shuts, up starts low and lightens', () {
    List<(String, double, int)> steps(FeedbackEvent event) => [
      for (final step in hapticPatterns[event]!.primitives) (step.name, step.scale, step.delayMs),
    ];
    expect(steps(FeedbackEvent.amountsHidden), [
      ('tick', 0.4, 0),
      ('tick', 0.6, 25),
      ('thud', 0.9, 35),
    ]);
    expect(steps(FeedbackEvent.amountsShown), [
      ('lowTick', 0.6, 0),
      ('tick', 0.5, 35),
      ('tick', 0.3, 25),
    ]);
  });

  group('events', () {
    // The web's patterns (apps/web/app/feedback/feedback.ts), in ms: vibrate, pause, vibrate...
    // Sounds are the web's too; gestures only vibrate there, and so here.
    const table = <FeedbackEvent, (List<int>, FeedbackSound?)>{
      FeedbackEvent.saved: ([12, 40, 18], FeedbackSound.expenseSaved),
      FeedbackEvent.incomeSaved: ([12, 40, 18], FeedbackSound.incomeSaved),
      FeedbackEvent.nearLimit: ([30], FeedbackSound.nearLimit),
      FeedbackEvent.overBudget: ([40, 60, 40], FeedbackSound.overBudget),
      FeedbackEvent.paid: ([10, 30, 10, 30, 24], FeedbackSound.paid),
      FeedbackEvent.deleted: ([14, 30, 8], null),
      FeedbackEvent.undo: ([8], FeedbackSound.undo),
      FeedbackEvent.thresholdCrossed: ([10], null),
      FeedbackEvent.pageChanged: ([15], null),
      FeedbackEvent.keyPressed: ([14], null),
      FeedbackEvent.amountCleared: ([20, 40, 10], null),
      // The app's own (the web has no ＋ of this kind, nor sheets that weigh): they only vibrate.
      FeedbackEvent.addPressed: ([20], null),
      FeedbackEvent.addReleased: ([10], null),
      FeedbackEvent.micPressed: ([12], null),
      FeedbackEvent.micReleased: ([6], null),
      FeedbackEvent.sheetOpened: ([18, 50, 6], null),
      FeedbackEvent.sheetClosed: ([16], null),
      // Home's eye and the widget's: the blind comes down and shuts, the blind goes up.
      FeedbackEvent.amountsHidden: ([6, 25, 8, 35, 22], null),
      FeedbackEvent.amountsShown: ([16, 35, 8, 25, 6], null),
      FeedbackEvent.wheelSpun: (
        [8, 18, 8, 20, 8, 21, 8, 22, 8, 24, 8, 25, 8, 27, 8, 30, 8, 34, 8, 39, 8, 50, 8, 114, 20],
        null,
      ),
    };

    test('each event maps to its haptic pattern and sound', () async {
      expect(table.keys.toSet(), FeedbackEvent.values.toSet(), reason: 'every event is covered');
      for (final entry in table.entries) {
        final platform = FakeFeedbackPlatform();
        final container = containerWith(platform);
        await started(container);
        container.read(feedbackProvider)(entry.key);
        await Future<void>.delayed(Duration.zero);
        final (waveform, sound) = entry.value;
        expect(platform.haptics, hasLength(1), reason: '${entry.key}');
        expect(platform.haptics.single.waveform, waveform, reason: '${entry.key}');
        expect(platform.sounds, sound == null ? isEmpty : [sound], reason: '${entry.key}');
      }
    });

    test('every pattern also has primitives, each with a scale between 0 and 1', () {
      for (final event in FeedbackEvent.values) {
        final pattern = hapticPatterns[event]!;
        expect(pattern.primitives, isNotEmpty, reason: '$event');
        for (final step in pattern.primitives) {
          expect(['click', 'tick', 'thud', 'lowTick'], contains(step.name), reason: '$event');
          expect(step.scale, inInclusiveRange(0.1, 1.0), reason: '$event');
          expect(step.delayMs, greaterThanOrEqualTo(0), reason: '$event');
        }
      }
    });

    test('the ＋ clicks like a real button, harder than the 🎤, going down and coming up', () {
      double strength(FeedbackEvent event) => hapticPatterns[event]!.primitives.single.scale;
      int length(FeedbackEvent event) => hapticPatterns[event]!.waveform.single;
      expect(hapticPatterns[FeedbackEvent.addPressed]!.primitives.single.name, 'click');
      expect(strength(FeedbackEvent.addPressed), greaterThan(strength(FeedbackEvent.addReleased)));
      expect(strength(FeedbackEvent.addPressed), greaterThan(strength(FeedbackEvent.micPressed)));
      expect(strength(FeedbackEvent.addReleased), greaterThan(strength(FeedbackEvent.micReleased)));
      expect(length(FeedbackEvent.addPressed), greaterThan(length(FeedbackEvent.micPressed)));
      expect(length(FeedbackEvent.addReleased), greaterThan(length(FeedbackEvent.micReleased)));
    });

    test('a sheet lands with a thud and shuts with a lighter one', () {
      final opened = hapticPatterns[FeedbackEvent.sheetOpened]!.primitives;
      final closed = hapticPatterns[FeedbackEvent.sheetClosed]!.primitives;
      expect(opened.first.name, 'thud');
      expect(closed.single.name, 'thud');
      expect(closed.single.scale, lessThan(opened.first.scale));
    });

    test(
      'the wheel ticks where easeOut crosses each twelfth of the sweep, and stops at its end',
      () {
        final waveform = hapticPatterns[FeedbackEvent.wheelSpun]!.waveform;
        // When each vibration starts, in ms from the sweep's start.
        final starts = <int>[];
        var at = 0;
        for (var i = 0; i < waveform.length; i++) {
          if (i.isEven) starts.add(at);
          at += waveform[i];
        }
        expect(starts, hasLength(13), reason: 'the start, 11 notches and the stop');
        const sweep = 520;
        expect(WambitoTokens.durationHop.inMilliseconds, sweep);
        for (var k = 1; k < 12; k++) {
          // Where the curve has covered k twelfths, found by bisection.
          var lo = 0.0, hi = 1.0;
          for (var i = 0; i < 40; i++) {
            final mid = (lo + hi) / 2;
            if (Curves.easeOut.transform(mid) < k / 12) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
          expect(starts[k], closeTo(lo * sweep, 2), reason: 'notch $k');
        }
        expect(starts.last, sweep, reason: 'the stop is where the figures settle');
        final gaps = [for (var k = 1; k < starts.length; k++) starts[k] - starts[k - 1]];
        for (var k = 1; k < gaps.length; k++) {
          expect(gaps[k], greaterThanOrEqualTo(gaps[k - 1]), reason: 'it only slows down');
        }
        final steps = hapticPatterns[FeedbackEvent.wheelSpun]!.primitives;
        expect(steps.last.name, 'click', reason: 'it stops with a click');
        expect(steps.take(12).every((step) => step.name == 'tick'), isTrue);
      },
    );

    test('the sound files are the web\'s, in the app\'s assets', () {
      expect(FeedbackSound.expenseSaved.asset, 'assets/sounds/expense-saved.mp3');
      expect(FeedbackSound.paid.asset, 'assets/sounds/paid.mp3');
      expect(FeedbackSound.undo.asset, 'assets/sounds/undo.mp3');
      expect(FeedbackSound.incomeSaved.asset, 'assets/sounds/income-saved.mp3');
      expect(FeedbackSound.nearLimit.asset, 'assets/sounds/near-limit.mp3');
      expect(FeedbackSound.overBudget.asset, 'assets/sounds/over-budget.mp3');
    });

    test('feedback never throws, whatever the phone does', () async {
      final platform = FakeFeedbackPlatform()..failure = PlatformException(code: 'no-motor');
      final container = containerWith(platform);
      for (final event in FeedbackEvent.values) {
        container.read(feedbackProvider)(event);
      }
      await Future<void>.delayed(Duration.zero);
      expect(platform.haptics, isEmpty);
    });

    test('the platform is warmed up once, when feedback is first used', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform);
      container.read(feedbackProvider);
      container.read(feedbackProvider);
      await Future<void>.delayed(Duration.zero);
      expect(platform.warmUps, 1);
    });
  });

  group('the sound setting', () {
    test('sounds are on by default, like the web\'s', () {
      final container = containerWith(FakeFeedbackPlatform());
      expect(container.read(soundEnabledProvider), isTrue);
    });

    test('a muted person who launches the app fresh never hears the first sound', () async {
      // Nothing listens to the setting first: feedback goes off the moment the app is up, before
      // the stored "off" has been read back.
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform, store: FakeSoundStore(false));
      container.read(feedbackProvider)(FeedbackEvent.saved);
      container.read(feedbackProvider)(FeedbackEvent.paid);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sounds, isEmpty);

      await container.read(soundEnabledProvider.notifier).ready;
      await container.read(vibrationEnabledProvider.notifier).ready;
      container.read(feedbackProvider)(FeedbackEvent.saved);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sounds, isEmpty, reason: 'and still muted once it is read');
      expect(platform.haptics, hasLength(1), reason: 'the sound setting leaves haptics alone');
    });

    test('until the setting is read nothing is heard, and after it sounds play', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform, store: FakeSoundStore(true));
      container.read(feedbackProvider)(FeedbackEvent.saved);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sounds, isEmpty, reason: 'not loaded yet is silent');
      await container.read(soundEnabledProvider.notifier).ready;
      container.read(feedbackProvider)(FeedbackEvent.saved);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sounds, [FeedbackSound.expenseSaved]);
    });

    test('feedback starts reading the setting as soon as it is built', () {
      final store = FakeSoundStore();
      final container = containerWith(FakeFeedbackPlatform(), store: store);
      container.read(feedbackProvider);
      expect(store.reads, 1);
    });

    test('a person who never chose hears sounds, once the setting is read', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform, store: FakeSoundStore());
      await started(container);
      expect(container.read(soundEnabledProvider), isTrue);
      container.read(feedbackProvider)(FeedbackEvent.undo);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sounds, [FeedbackSound.undo]);
    });

    test('a store that cannot be read leaves sounds on, once that is known', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform, store: _BrokenStore());
      await started(container);
      container.read(feedbackProvider)(FeedbackEvent.undo);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sounds, [FeedbackSound.undo]);
    });

    test('mute stops sounds, not haptics', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform);
      await started(container);
      await container.read(soundEnabledProvider.notifier).set(false);
      container.read(feedbackProvider)(FeedbackEvent.paid);
      container.read(feedbackProvider)(FeedbackEvent.undo);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sounds, isEmpty);
      expect(platform.haptics.map((p) => p.waveform), [
        [10, 30, 10, 30, 24],
        [8],
      ]);
    });

    test('turning sounds back on plays them again', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform);
      await started(container);
      final setting = container.read(soundEnabledProvider.notifier);
      await setting.set(false);
      await setting.set(true);
      container.read(feedbackProvider)(FeedbackEvent.saved);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sounds, [FeedbackSound.expenseSaved]);
    });

    test('the choice is kept: a new start reads it back', () async {
      final store = FakeSoundStore();
      final first = containerWith(FakeFeedbackPlatform(), store: store);
      await first.read(soundEnabledProvider.notifier).set(false);
      expect(store.value, isFalse);

      final second = containerWith(FakeFeedbackPlatform(), store: store);
      second.listen(soundEnabledProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(second.read(soundEnabledProvider), isFalse);
    });

    test(
      'a store that cannot be read leaves sounds on, and one that cannot be written does not throw',
      () async {
        final store = _BrokenStore();
        final container = containerWith(FakeFeedbackPlatform(), store: store);
        container.listen(soundEnabledProvider, (_, _) {});
        await Future<void>.delayed(Duration.zero);
        expect(container.read(soundEnabledProvider), isTrue);
        await container.read(soundEnabledProvider.notifier).set(false);
        expect(container.read(soundEnabledProvider), isFalse, reason: 'for this run, at least');
      },
    );

    test('a choice made while the old one is still being read wins', () async {
      final store = FakeSoundStore(true);
      final container = containerWith(FakeFeedbackPlatform(), store: store);
      container.listen(soundEnabledProvider, (_, _) {});
      await container.read(soundEnabledProvider.notifier).set(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(soundEnabledProvider), isFalse);
    });
  });

  group('the vibration setting', () {
    test('vibration is on by default', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform, vibrationStore: FakeSoundStore());
      await started(container);
      expect(container.read(vibrationEnabledProvider), isTrue);
      container.read(feedbackProvider)(FeedbackEvent.undo);
      await Future<void>.delayed(Duration.zero);
      expect(platform.haptics, hasLength(1));
    });

    test('with vibration off, no event vibrates, and sounds still play', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform);
      await started(container);
      await container.read(vibrationEnabledProvider.notifier).set(false);
      container.read(feedbackProvider)(FeedbackEvent.paid);
      container.read(feedbackProvider)(FeedbackEvent.keyPressed);
      container.read(feedbackProvider)(FeedbackEvent.thresholdCrossed);
      await Future<void>.delayed(Duration.zero);
      expect(platform.haptics, isEmpty);
      expect(platform.sounds, [FeedbackSound.paid]);
    });

    test('turning vibration back on vibrates again', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform);
      await started(container);
      final setting = container.read(vibrationEnabledProvider.notifier);
      await setting.set(false);
      await setting.set(true);
      container.read(feedbackProvider)(FeedbackEvent.undo);
      await Future<void>.delayed(Duration.zero);
      expect(platform.haptics, hasLength(1));
    });

    test(
      'a person who turned vibration off never feels the first one after a fresh start',
      () async {
        final platform = FakeFeedbackPlatform();
        final container = containerWith(platform, vibrationStore: FakeSoundStore(false));
        container.read(feedbackProvider)(FeedbackEvent.saved);
        await Future<void>.delayed(Duration.zero);
        expect(platform.haptics, isEmpty, reason: 'not read yet is quiet');
        await container.read(vibrationEnabledProvider.notifier).ready;
        container.read(feedbackProvider)(FeedbackEvent.saved);
        await Future<void>.delayed(Duration.zero);
        expect(platform.haptics, isEmpty, reason: 'and still off once it is read');
      },
    );

    test('the choice is kept on its own key: a new start reads it back, sound untouched', () async {
      final vibration = FakeSoundStore();
      final sound = FakeSoundStore();
      final first = containerWith(FakeFeedbackPlatform(), store: sound, vibrationStore: vibration);
      await first.read(vibrationEnabledProvider.notifier).set(false);
      expect(vibration.value, isFalse);
      expect(sound.value, isNull);

      final second = containerWith(FakeFeedbackPlatform(), store: sound, vibrationStore: vibration);
      second.listen(vibrationEnabledProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(second.read(vibrationEnabledProvider), isFalse);
      expect(second.read(soundEnabledProvider), isTrue);
    });

    test('a store that cannot be read leaves vibration on, and one that cannot be written does not throw', () async {
      final platform = FakeFeedbackPlatform();
      final container = containerWith(platform, vibrationStore: _BrokenStore());
      await started(container);
      container.read(feedbackProvider)(FeedbackEvent.undo);
      await Future<void>.delayed(Duration.zero);
      expect(platform.haptics, hasLength(1));
      await container.read(vibrationEnabledProvider.notifier).set(false);
      expect(container.read(vibrationEnabledProvider), isFalse);
    });
  });

  group('celebration', () {
    test('each celebration is a new beat, so the same one twice still counts', () {
      final container = containerWith(FakeFeedbackPlatform());
      expect(container.read(celebrationProvider), 0);
      container.read(celebrationProvider.notifier).celebrate();
      container.read(celebrationProvider.notifier).celebrate();
      expect(container.read(celebrationProvider), 2);
    });
  });

  group('the Android channels', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      for (final name in ['wambito/haptics', 'wambito/sounds']) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          calls.add(call);
          return null;
        });
      }
    });

    tearDown(() {
      for (final name in ['wambito/haptics', 'wambito/sounds']) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
    });

    test('a pattern goes to wambito/haptics as its timings and its primitives', () async {
      await const ChannelFeedbackPlatform().vibrate(hapticPatterns[FeedbackEvent.deleted]!);
      expect(calls.single.method, 'vibrate');
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['waveform'], [14, 30, 8]);
      expect(args['primitives'], [
        {'name': 'click', 'scale': 0.8, 'delay': 0},
        {'name': 'tick', 'scale': 0.5, 'delay': 30},
      ]);
    });

    test('a sound goes to wambito/sounds as its asset', () async {
      await const ChannelFeedbackPlatform().play(FeedbackSound.paid);
      expect(calls.single.method, 'play');
      expect(calls.single.arguments, {'asset': 'assets/sounds/paid.mp3'});
    });

    test('warming up asks the speaker to load every sound', () async {
      await const ChannelFeedbackPlatform().warmUp();
      expect(calls.single.method, 'preload');
      expect(calls.single.arguments, {
        'assets': [for (final s in FeedbackSound.values) s.asset],
      });
    });

    test('a phone with no such channel (a test, say) is not an error', () async {
      messenger.setMockMethodCallHandler(const MethodChannel('wambito/haptics'), null);
      await const ChannelFeedbackPlatform().vibrate(hapticPatterns[FeedbackEvent.undo]!);
    });
  });
}

class _BrokenStore implements SoundSettingStore {
  @override
  Future<bool?> read() async => throw PlatformException(code: 'keystore');

  @override
  Future<void> write(bool on) async => throw PlatformException(code: 'keystore');

  @override
  Future<void> clear() async => throw PlatformException(code: 'keystore');
}
