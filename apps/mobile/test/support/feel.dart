import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';

import '../feedback/fakes.dart';

/// [child] under a scope whose motor is [platform], with sound and vibration known and on (or
/// [vibration] off): a component's feel can be read from `platform.haptics`.
Future<FakeFeedbackPlatform> pumpFelt(
  WidgetTester tester,
  Widget child, {
  bool vibration = true,
}) async {
  final platform = FakeFeedbackPlatform();
  final container = ProviderContainer(
    overrides: [
      feedbackPlatformProvider.overrideWithValue(platform),
      soundSettingStoreProvider.overrideWithValue(FakeSoundStore()),
      vibrationSettingStoreProvider.overrideWithValue(FakeSoundStore(vibration)),
    ],
  );
  addTearDown(container.dispose);
  container.read(feedbackProvider);
  await container.read(vibrationEnabledProvider.notifier).ready;
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: child));
  return platform;
}

/// The events [platform] vibrated, by their patterns.
List<FeedbackEvent?> feltEvents(FakeFeedbackPlatform platform) => [
  for (final pattern in platform.haptics)
    hapticPatterns.entries.where((e) => e.value == pattern).map((e) => e.key).firstOrNull,
];
