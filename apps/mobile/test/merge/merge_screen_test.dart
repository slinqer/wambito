import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/merge/merge_controller.dart';
import 'package:wambito/merge/merge_offer.dart';
import 'package:wambito/merge/merge_screen.dart';

import '../support/ui_app.dart';

/// A merge standing still at [shown], recording what the screen asks of it.
class _Merge extends MergeController {
  _Merge(this.shown);

  final MergeState shown;
  final asked = <String>[];

  @override
  MergeState build() => shown;

  @override
  Future<void> cancel() async => asked.add('cancel');

  @override
  Future<void> keepAccountOnly() async => asked.add('keepAccountOnly');

  @override
  Future<void> run() async => asked.add('run');
}

void main() {
  Future<_Merge> pumpScreen(WidgetTester tester, MergeState state) async {
    final merge = _Merge(state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mergeControllerProvider.overrideWith(() => merge)],
        child: uiApp(const SizedBox(height: 900, child: MergeScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return merge;
  }

  testWidgets('the currency stop names both currencies', (tester) async {
    final merge = await pumpScreen(tester, const MergeCurrencyStop(phone: 'USD', account: 'COP'));
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.mergeCurrencyStop('COP', 'USD')), findsOneWidget);
    expect(find.textContaining('COP'), findsOneWidget);
    expect(find.textContaining('USD'), findsOneWidget);

    await tester.tap(find.byKey(const Key('merge.cancel')));
    await tester.pumpAndSettle();
    expect(merge.asked, ['cancel']);

    // Keeping only the account's data asks first.
    await tester.tap(find.byKey(const Key('merge.keepAccount')));
    await tester.pumpAndSettle();
    expect(merge.asked, ['cancel']);
    await tester.tap(find.byKey(const Key('merge.keepAccountConfirm')));
    await tester.pumpAndSettle();
    expect(merge.asked, ['cancel', 'keepAccountOnly']);
  });

  testWidgets('the offer says the phone\'s recovery key stops working', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      uiApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await askMerge(context, 'ana@wambito.test'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.mergeOfferQuestion), findsOneWidget);
    expect(find.text(l10n.mergeOfferKeyNote), findsOneWidget);

    await tester.tap(find.byKey(const Key('merge.yes')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('closing the offer answers no', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      uiApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await askMerge(context, 'ana@wambito.test'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
