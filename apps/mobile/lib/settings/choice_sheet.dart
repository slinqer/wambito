// The sheet behind Preferencias' Idioma and Tema rows (the web's `ChoiceSheet.tsx`): today's
// `Choices` inside an `LkSheet`. A pick applies at once and the sheet closes.
import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';
import '../ui/sheet.dart';
import 'settings_parts.dart';

abstract final class ChoicesSheet {
  static Future<void> show<T>(
    BuildContext context, {
    required String title,
    String? hint,
    required T value,
    required List<Choice<T>> options,
    required ValueChanged<T> onChanged,
  }) => LkSheet.show<void>(
    context,
    title: title,
    children: [
      Builder(
        builder: (sheet) => Padding(
          padding: const EdgeInsets.only(top: WambitoTokens.space3),
          child: Choices<T>(
            legend: title,
            hint: hint,
            value: value,
            options: options,
            onChanged: (next) {
              onChanged(next);
              Navigator.of(sheet).pop();
            },
          ),
        ),
      ),
    ],
  );
}
