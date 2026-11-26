import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// An amount with its currency, as the app writes it: "4,10 €", "€4.10", "1.234 USD", "−12,50 €".
final amountPattern = RegExp(r'(\d[\d.,   ]*\s?(€|\$|£|\b[A-Z]{3}\b))|((€|\$|£)\s?\d)');

/// Fails when any text on screen, or any label a screen reader reads, holds an amount.
void expectNoAmounts(WidgetTester tester) {
  final found = <String>[];
  for (final element in find.byType(RichText, skipOffstage: false).evaluate()) {
    final text = (element.widget as RichText).text.toPlainText();
    if (amountPattern.hasMatch(text)) found.add(text);
  }
  final root = tester.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
  void visit(SemanticsNode node) {
    for (final text in [node.label, node.value, node.hint]) {
      if (amountPattern.hasMatch(text)) found.add(text);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  if (root != null) visit(root);
  if (found.isNotEmpty) fail('Amounts still on screen: $found');
}
