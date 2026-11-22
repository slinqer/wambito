// The welcome's import step for an encrypted (`preview`) account: the server's import waits for
// encryption, so the step says so, offers no sources or picker, and moves on with "Siguiente".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/import/import_state.dart';
import 'package:wambito/welcome/import_step.dart';

import '../support/ui_app.dart';

void main() {
  void noop() {}

  Widget step({required bool preview}) => uiApp(
    SizedBox(
      height: 800,
      child: ImportStep(
        state: const ImportSources(),
        preview: preview,
        onChoose: noop,
        onConfirm: noop,
        onDiscard: noop,
        onSource: ({required budge}) {},
        onBack: noop,
        onSkip: noop,
        onNext: noop,
      ),
    ),
  );

  testWidgets('preview: the notice, no sources', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(step(preview: true));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('welcome.import.comingSoon')), findsOneWidget);
    expect(find.bySemanticsLabel('Próximamente con cifrado'), findsWidgets);
    expect(find.byKey(const Key('import.choose')), findsNothing);
    handle.dispose();
  });

  testWidgets('plain: the sources, no notice', (t) async {
    await t.pumpWidget(step(preview: false));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('welcome.import.comingSoon')), findsNothing);
  });
}
