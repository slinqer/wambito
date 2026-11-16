// "Más opciones" of the web's add sheet (AddTransactionSheet.tsx): the row that opens it
// (app.css `.lk-more-row`), then the date, pending, Repetir and the note.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api/gen/wambito_api.dart' show CreateTransactionRepeatFrequencyEnum;
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/input_box.dart';
import '../ui/lk_theme.dart';
import '../ui/pressable.dart';
import '../ui/segmented_control.dart';
import 'add_form.dart';
import '../ui/lk_icons.dart';

/// `.lk-more-row`: a 44px button with a 2px `control-edge` border on the row colour, holding
/// "Más opciones", the date and status in muted text, and ▴ or ▾ at the end.
class MoreRow extends StatelessWidget {
  const MoreRow({
    super.key,
    required this.open,
    required this.onToggle,
    required this.title,
    required this.summary,
  });

  final bool open;
  final VoidCallback onToggle;
  final String title;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final radius = LkSurface.radius(LkRadius.md);
    return Pressable(
      onPressed: onToggle,
      expanded: open,
      label: '$title, $summary',
      builder: (context, state) => RingBox(
        radius: state.focusVisible ? radius : null,
        color: colors.focus,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceRow,
              borderRadius: radius,
              border: Border.all(color: colors.controlEdge, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WambitoTokens.space3),
              child: Row(
                spacing: WambitoTokens.space2,
                children: [
                  BlinkLine(
                    style: LkText.label,
                    child: Text(title, style: LkText.label.copyWith(color: colors.ink)),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BlinkLine(
                        style: LkText.label,
                        child: Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LkText.label.copyWith(color: colors.inkMuted),
                        ),
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: BlinkLine(
                      style: LkText.label,
                      child: Text(
                        open ? '▴' : '▾',
                        style: LkText.label.copyWith(color: colors.ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `<label class="flex flex-col gap-(--space-1) text-[13px] font-bold text-ink-muted">`: a field's
/// caption over the field.
class FieldLabel extends StatelessWidget {
  const FieldLabel({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space1,
      children: [
        ExcludeSemantics(
          child: BlinkLine(
            style: LkText.fieldLabel,
            child: Text(label, style: LkText.fieldLabel.copyWith(color: colors.inkMuted)),
          ),
        ),
        child,
      ],
    );
  }
}

/// The date as the field shows it: the language's own order and separator, two digits each
/// (`21/10/2026` in Spanish, `10/21/2026` in English).
String dateFieldText(String date, String locale) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  return DateFormat(locale == 'en' ? 'MM/dd/yyyy' : 'dd/MM/yyyy').format(parsed);
}

/// The web's `<input type="date" class="lk-input min-h-11">`: the date as text, and the browser's
/// little calendar after it. Tapping it opens the date picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.date,
    required this.locale,
    required this.onTap,
    this.invalid = false,
  });

  final String label;

  /// `YYYY-MM-DD`; empty when none.
  final String date;
  final String locale;
  final VoidCallback onTap;

  /// The field has a mistake: its border is `over` (`border-over`).
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final text = date.isEmpty ? '' : dateFieldText(date, locale);
    return Pressable(
      onPressed: onTap,
      label: '$label, $text',
      builder: (context, state) => FieldLabel(
        label: label,
        child: InputBox(
          focused: state.focusVisible,
          borderColor: invalid ? colors.over : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BlinkLine(
                style: LkText.input,
                child: Text(text, style: LkText.input.copyWith(color: colors.ink)),
              ),
              // Chrome's calendar button starts 24px after the text and draws a 10px glyph inside
              // its own padding.
              const SizedBox(width: 34.5),
              const CustomPaint(size: Size(10, 12), painter: _CalendarPainter()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The end date with a way to take it out again: the browser's own date control clears itself, this
/// one has no such control, so a small button sits at the end of the field once there is a date.
class ClearableDate extends StatelessWidget {
  const ClearableDate({
    super.key,
    required this.child,
    required this.clearLabel,
    required this.clearKey,
    required this.onClear,
  });

  final Widget child;
  final String clearLabel;
  final Key clearKey;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Stack(
      children: [
        child,
        if (onClear != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Pressable(
              key: clearKey,
              onPressed: onClear,
              label: clearLabel,
              builder: (context, state) => SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: LkIcon(
                    LkIconName.close,
                    size: 18,
                    color: state.focusVisible ? colors.focus : colors.inkMuted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The calendar Chrome draws at the end of a date field: black, whatever the page's colours.
class _CalendarPainter extends CustomPainter {
  const _CalendarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = const Color(0xFF000000);
    final line = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    // The two rings the pages hang on.
    canvas.drawRect(const Rect.fromLTWH(2, 0, 1.2, 2.4), ink);
    canvas.drawRect(const Rect.fromLTWH(6.8, 0, 1.2, 2.4), ink);
    // The sheet, with a heavy header.
    canvas.drawRect(const Rect.fromLTWH(0, 1.6, 10, 3), ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0.6, 2.2, 8.8, 9.2), const Radius.circular(0.6)),
      line,
    );
  }

  @override
  bool shouldRepaint(_CalendarPainter old) => false;
}

/// The web's pending checkbox: `<label class="flex min-h-11 items-center gap-(--space-2) text-[14px]
/// font-bold text-ink">` around a 20px native checkbox with the brand as its accent.
class PendingCheckbox extends StatelessWidget {
  const PendingCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Pressable(
      onPressed: () => onChanged(!value),
      checked: value,
      label: label,
      builder: (context, state) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          spacing: WambitoTokens.space2,
          children: [
            CustomPaint(
              size: const Size.square(20),
              painter: _CheckboxPainter(
                checked: value,
                focused: state.focusVisible,
                accent: colors.brand,
                onAccent: colors.onBrand,
              ),
            ),
            Flexible(
              child: BlinkLine(
                style: LkText.bodySm,
                child: Text(label, style: LkText.bodySm.copyWith(color: colors.ink)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chrome's checkbox: 20px, with the accent as its fill and a white tick when checked, a grey
/// outline on white when not, and, with the keyboard on it, the browser's focus ring: a white
/// edge outside a 2px blue one.
class _CheckboxPainter extends CustomPainter {
  const _CheckboxPainter({
    required this.checked,
    required this.focused,
    required this.accent,
    required this.onAccent,
  });

  final bool checked;
  final bool focused;
  final Color accent;
  final Color onAccent;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3));
    if (focused) {
      canvas.drawRRect(
        box.inflate(2),
        Paint()
          ..color = const Color(0xFF005FCC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawRRect(
        box.inflate(3.5),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    if (checked) {
      canvas.drawRRect(box, Paint()..color = accent);
      final tick = Path()
        ..moveTo(4.6, 10.4)
        ..lineTo(8.4, 14.2)
        ..lineTo(15.6, 6.2);
      canvas.drawPath(
        tick,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.miter,
      );
    } else {
      canvas.drawRRect(box, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRRect(
        box.deflate(0.5),
        Paint()
          ..color = const Color(0xFF767676)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckboxPainter old) =>
      old.checked != checked ||
      old.focused != focused ||
      old.accent != accent ||
      old.onAccent != onAccent;
}

/// The web's `<textarea class="lk-input min-h-11 ..." rows="2" maxlength="1000">`: two lines of the
/// note, scrolling inside the box for more.
class NoteField extends StatelessWidget {
  const NoteField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return FieldLabel(
      label: label,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) => InputBox(
          focused: focusNode.hasFocus,
          child: Semantics(
            label: label,
            textField: true,
            multiline: true,
            child: Transform.translate(
              offset: Offset(0, cssBaselineShift(LkText.input)),
              child: EditableText(
                key: const Key('add.note'),
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                style: LkText.input.copyWith(color: colors.ink),
                cursorColor: colors.ink,
                backgroundCursorColor: colors.inkMuted,
                selectionColor: colors.brand.withValues(alpha: 0.4),
                minLines: 2,
                maxLines: 2,
                keyboardType: TextInputType.multiline,
                inputFormatters: [LengthLimitingTextInputFormatter(1000)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The date, pending, "Repetir" and the note: what "Más opciones" opens. Repetir (adding only)
/// shows the recurring form's choices the sheet does not already have: monthly or yearly and an
/// optional end; the day, the month of a yearly one and the start come from the date.
class MoreDetails extends StatelessWidget {
  const MoreDetails({
    super.key,
    required this.form,
    required this.l10n,
    required this.note,
    required this.noteFocus,
    required this.onPickDate,
    required this.onPickEndDate,
  });

  final AddForm form;
  final AppLocalizations l10n;
  final TextEditingController note;
  final FocusNode noteFocus;
  final VoidCallback onPickDate;
  final VoidCallback onPickEndDate;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: [
        DateField(
          key: const Key('add.date'),
          label: l10n.addDateLabel,
          date: form.date,
          locale: l10n.localeName,
          onTap: onPickDate,
        ),
        PendingCheckbox(
          key: const Key('add.pending'),
          label: l10n.addPendingLabel,
          value: form.pending,
          onChanged: (value) => form.pending = value,
        ),
        if (form.editing == null)
          PendingCheckbox(
            key: const Key('add.repeat'),
            label: l10n.addRepeatLabel,
            value: form.repeat,
            onChanged: (value) => form.repeat = value,
          ),
        if (form.repeat)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space2,
            children: [
              SegmentedControl<CreateTransactionRepeatFrequencyEnum>(
                label: l10n.recurringFormFrequencyLabel,
                value: form.frequency,
                onChanged: form.setFrequency,
                options: [
                  SegmentOption(
                    CreateTransactionRepeatFrequencyEnum.monthly,
                    l10n.recurringFormMonthly,
                    key: const Key('add.repeat.monthly'),
                  ),
                  SegmentOption(
                    CreateTransactionRepeatFrequencyEnum.yearly,
                    l10n.recurringFormYearly,
                    key: const Key('add.repeat.yearly'),
                  ),
                ],
              ),
              ClearableDate(
                clearLabel: l10n.recurringFormClearEnd,
                clearKey: const Key('add.repeat.end.clear'),
                onClear: form.endDate.isEmpty ? null : () => form.setEndDate(''),
                child: DateField(
                  key: const Key('add.repeat.end'),
                  label: l10n.recurringFormEndLabel,
                  date: form.endDate,
                  locale: l10n.localeName,
                  invalid: form.endBeforeDate,
                  onTap: onPickEndDate,
                ),
              ),
              Semantics(
                liveRegion: form.endBeforeDate,
                child: Text(
                  form.endBeforeDate ? l10n.addRepeatEndBefore : l10n.addRepeatHint,
                  key: const Key('add.repeat.note'),
                  style: LkText.fieldLabel.copyWith(
                    color: form.endBeforeDate ? colors.over : colors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        NoteField(
          label: l10n.addNoteLabel,
          controller: note,
          focusNode: noteFocus,
          onChanged: form.setNote,
        ),
      ],
    );
  }
}
