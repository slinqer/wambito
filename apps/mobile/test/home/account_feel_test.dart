// The account button clicks, smaller and quieter than the 🎤, as its menu opens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';

import '../feedback/fakes.dart';
import '../support/feel.dart';
import 'home_harness.dart';

void main() {
  testWidgets('tapping the account button plays its click', (t) async {
    final platform = FakeFeedbackPlatform();
    final harness = await pumpHome(
      t,
      monthWithBudgets(),
      withMenu: true,
      overrides: [
        feedbackPlatformProvider.overrideWithValue(platform),
        soundSettingStoreProvider.overrideWithValue(FakeSoundStore()),
        vibrationSettingStoreProvider.overrideWithValue(FakeSoundStore()),
      ],
    );
    await harness.container.read(vibrationEnabledProvider.notifier).ready;
    await t.tap(find.byKey(const Key('home.account')));
    await t.pumpAndSettle();
    expect(feltEvents(platform), contains(FeedbackEvent.accountPressed));
  });
}
