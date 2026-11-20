// The recovery key's field (spec 2026-11-20 section 3): the web's
// apps/web/app/features/vault/recovery-key-input.ts. Unlock and the recovery-key sign-in use it;
// `parseRecoveryKey` (lib/crypto/recovery.dart) stays the judge of what is typed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crypto/recovery.dart' show crockford;
import '../l10n/app_localizations.dart';
import '../ui/press_button.dart';
import '../ui/web_text_field.dart';

/// A full key: 26 data characters and a check character, shown in groups of four.
const _keyChars = 27;
const _group = 4;

/// The key's alphabet plus the look-alikes the parser forgives (O, I, L).
final _allowed = {...crockford.split(''), 'O', 'I', 'L'};

/// The typed text without anything outside the alphabet, upper case, whole (not capped).
String _significant(String text) {
  final out = StringBuffer();
  for (final char in text.toUpperCase().split('')) {
    if (_allowed.contains(char)) out.write(char);
  }
  return out.toString();
}

String _grouped(String chars) => [
  for (var i = 0; i < chars.length; i += _group)
    chars.substring(i, i + _group > chars.length ? chars.length : i + _group),
].join('-');

/// The recovery key as the field shows it: upper case, only the key's alphabet (plus `O`, `I`, `L`,
/// which the parser reads as `0`, `1`, `1`), at most 27 characters, a dash after every fourth.
/// Spaces, new lines and dashes in the input are dropped, so a paste in any shape regroups.
String groupRecoveryKey(String text) {
  final chars = _significant(text);
  return _grouped(chars.length > _keyChars ? chars.substring(0, _keyChars) : chars);
}

/// The index in a grouped text just after its [count]-th key character.
int _caretAfter(int count) => count <= 0 ? 0 : count + (count - 1) ~/ _group;

/// An edit of the field: [next] is what the field holds after the change and [caret] where its
/// caret is. Returns the grouped text and the caret to set, which stays after the same key
/// characters. Backspace right after a dash removes only the dash, which regrouping would put back,
/// so it removes the character before the dash instead.
({String text, int caret}) groupRecoveryKeyEdit(String previous, String next, int caret) {
  final at = caret.clamp(0, next.length);
  var before = _significant(next.substring(0, at));
  var chars = _significant(next);
  if (next.length < previous.length && chars == _significant(previous) && before.isNotEmpty) {
    before = before.substring(0, before.length - 1);
    chars = before + chars.substring(before.length + 1);
  }
  if (chars.length > _keyChars) chars = chars.substring(0, _keyChars);
  final kept = before.length < chars.length ? before.length : chars.length;
  return (text: _grouped(chars), caret: _caretAfter(kept));
}

/// Whether the text holds all 27 characters of a key.
bool isFullRecoveryKey(String text) => _significant(text).length == _keyChars;

/// [groupRecoveryKeyEdit] as the field's formatter: every change (typing, deleting, a paste from
/// the phone's menu) comes out grouped, with the caret after the same key characters.
class RecoveryKeyFormatter extends TextInputFormatter {
  const RecoveryKeyFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final selection = newValue.selection;
    final caret = selection.isValid ? selection.extentOffset : newValue.text.length;
    final edit = groupRecoveryKeyEdit(oldValue.text, newValue.text, caret);
    // No composing range back: the keyboard must not keep composing over text this rewrote (a
    // known source of doubled or garbled characters on some keyboards, Samsung's among them).
    return TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.caret),
      composing: TextRange.empty,
    );
  }
}

/// The recovery key's one field (the web's `RecoveryKeyField.tsx`): it shows the key in groups of
/// four while it is typed, regroups a paste in any shape and keeps the caret after the same
/// characters; "Paste" in the field reads the clipboard (an empty or refused read does nothing).
class RecoveryKeyField extends StatefulWidget {
  const RecoveryKeyField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.fieldKey,
    required this.pasteKey,
    this.invalid = false,
    this.readOnly = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The key of the [EditableText] inside, which tests type into.
  final Key fieldKey;

  /// The key of the "Paste" button.
  final Key pasteKey;
  final bool invalid;
  final bool readOnly;
  final bool autofocus;

  /// Told the grouped text after every change, a paste included.
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<RecoveryKeyField> createState() => _RecoveryKeyFieldState();
}

class _RecoveryKeyFieldState extends State<RecoveryKeyField> {
  Future<void> _paste() async {
    final String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      return;
    }
    // The screen may have gone (or the field turned read-only) while the clipboard answered.
    if (!mounted || widget.readOnly || text == null || text.isEmpty) return;
    final grouped = groupRecoveryKey(text);
    widget.controller.value = TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
    widget.onChanged?.call(grouped);
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WebTextField(
      fieldKey: widget.fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      label: l10n.vaultUnlockLabel,
      placeholder: l10n.vaultUnlockPlaceholder,
      invalid: widget.invalid,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      // A keyboard that composes nothing (no predictions, no autocorrect) in capitals: the
      // formatter rewrites every change, which a composing keyboard garbles.
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.characters,
      enableIMEPersonalizedLearning: false,
      inputFormatters: const [RecoveryKeyFormatter()],
      textInputAction: TextInputAction.done,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      trailing: PressButton.text(
        l10n.vaultUnlockPaste,
        key: widget.pasteKey,
        tone: PressTone.ghost,
        size: PressSize.sm,
        onPressed: widget.readOnly ? null : () => unawaited(_paste()),
      ),
    );
  }
}
