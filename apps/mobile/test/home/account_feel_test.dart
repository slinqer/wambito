// The account button clicks, smaller and quieter than the 🎤, as its menu opens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/ui/lk_icons.dart';

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

  testWidgets('the account icon is the outline one, and the solid one while its menu is open', (
    t,
  ) async {
    await pumpHome(t, monthWithBudgets(), withMenu: true);
    Finder user(LkIconVariant variant) => find.descendant(
      of: find.byKey(const Key('home.account')),
      matching: find.byWidgetPredicate(
        (w) => w is LkIcon && w.name == LkIconName.user && w.variant == variant,
      ),
    );
    expect(user(LkIconVariant.outline), findsOneWidget);
    await t.tap(find.byKey(const Key('home.account')));
    await t.pumpAndSettle();
    expect(user(LkIconVariant.filled), findsOneWidget);
  });
}
