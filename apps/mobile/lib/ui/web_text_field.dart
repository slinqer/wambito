// The web's text input (`<input className="lk-input ...">`, apps/web/app/features/sign-in/SignIn.tsx).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import '../theme/text_styles.dart';
import 'input_box.dart';
import 'lk_theme.dart';

/// A one-line text field in the web's `.lk-input` box: a sunken box with a 2px border (the
/// theme's `over` on a mistake), the page's 16px text in it, a muted placeholder in the regular
/// weight, and the focus ring around the box while it has the focus.
///
/// [fieldKey] is the key of the [EditableText] inside, which tests type into. A tap anywhere on
/// the box focuses it and opens the keyboard.
class WebTextField extends StatefulWidget {
  const WebTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.fieldKey,
    required this.label,
    this.placeholder = '',
    this.invalid = false,
    this.readOnly = false,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.maxLines = 1,
    this.inputMinHeight = 36,
    this.enableSuggestions = false,
    this.leading,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Key fieldKey;

  /// The field's name for assistive technology (its visible label's text).
  final String label;
  final String placeholder;
  final bool invalid;
  final bool readOnly;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  /// The input's own least height inside the box: `min-h-9` (36) on the sign-in fields; a field
  /// with only `min-h-11` on the box is as tall as its line (24 for the page's 16px text).
  final double inputMinHeight;

  /// How many lines show before it scrolls: the web's `<textarea rows>`; one is the plain input.
  final int maxLines;

  /// Whether the keyboard's suggestion strip shows. Off for a code or an address; on for a sentence
  /// the person types. Autocorrect stays off either way: it must never rewrite an amount.
  final bool enableSuggestions;

  /// Something before the text inside the box (the search field's 🔍), 8px from it.
  final Widget? leading;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<WebTextField> createState() => _WebTextFieldState();
}

class _WebTextFieldState extends State<WebTextField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(WebTextField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_changed);
      widget.focusNode.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _tap() {
    widget.focusNode.requestFocus();
    editableStateBelow(context)?.requestKeyboard();
  }

  void _longPress() => showEditMenu(context, widget.focusNode);

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final text = LkText.copy;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.readOnly ? null : _tap,
      onLongPress: widget.readOnly ? null : _longPress,
      child: InputBox(
        focused: widget.focusNode.hasFocus,
        borderColor: widget.invalid ? colors.over : null,
        child: ConstrainedBox(
          // `min-h-9`: the input inside the box.
          constraints: BoxConstraints(minHeight: widget.inputMinHeight),
          child: Semantics(
            label: widget.label,
            textField: true,
            child: _withLeading(
              Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (widget.controller.text.isEmpty)
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: Text(
                          widget.placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.copyWith(color: colors.inkMuted, fontWeight: FontWeight.w400),
                        ),
                      ),
                    ),
                  EditableText(
                    key: widget.fieldKey,
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    style: text.copyWith(color: colors.ink),
                    cursorColor: colors.ink,
                    backgroundCursorColor: colors.inkMuted,
                    selectionColor: colors.brand.withValues(alpha: 0.4),
                    // The phone's own selection: a long press shows its menu, with "Pegar".
                    selectionControls: materialTextSelectionHandleControls,
                    contextMenuBuilder: (context, state) =>
                        AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                    maxLines: widget.maxLines,
                    inputFormatters: widget.inputFormatters,
                    // The box around it takes the taps and the long press (the field's own are rudimentary).
                    rendererIgnoresPointer: true,
                    readOnly: widget.readOnly,
                    autofocus: widget.autofocus,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    autofillHints: widget.autofillHints,
                    autocorrect: false,
                    enableSuggestions: widget.enableSuggestions,
                    onSubmitted: widget.onSubmitted,
                    onChanged: widget.onChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _withLeading(Widget field) {
    final leading = widget.leading;
    if (leading == null) return field;
    return Row(
      spacing: 8,
      children: [
        leading,
        Expanded(child: field),
      ],
    );
  }
}

/// The [EditableTextState] below [context]'s element: asked to show the keyboard or the menu when
/// the box around a bare [EditableText] is tapped or long-pressed.
EditableTextState? editableStateBelow(BuildContext context) {
  EditableTextState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is EditableTextState) {
      found = element.state as EditableTextState;
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return found;
}

/// A long press on a bare [EditableText]'s box: the field takes the focus and the phone's own menu
/// shows, with "Pegar" (the person copied a code or an address elsewhere). The menu needs the focus
/// to have settled, so when it cannot show at once it does after the next frame.
void showEditMenu(BuildContext context, FocusNode focusNode) {
  focusNode.requestFocus();
  final state = editableStateBelow(context);
  if (state == null) return;
  state.requestKeyboard();
  if (state.showToolbar()) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) editableStateBelow(context)?.showToolbar();
  });
  WidgetsBinding.instance.scheduleFrame();
}
