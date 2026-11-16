// The web's RecurringForm and the sheets around it (apps/web/app/features/recurring/RecurringForm.tsx
// and the page's delete question): expense or income, the amount on the shared keypad, a name, its
// category, monthly or yearly, the day of the month (a later day than a month has falls on its last),
// the month for a yearly one (required: nothing is sent without it), the start (today by default)
// and an optional end.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../add/keypad_input.dart';
import '../add/more_options.dart' show ClearableDate, DateField, FieldLabel;
import '../api/gen/wambito_api.dart';
import '../home/category_look.dart';
import '../home/home_format.dart';
import '../home/home_repository.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/amount_field.dart';
import '../ui/category_chip.dart';
import '../ui/confirm_sheet.dart';
import '../ui/input_box.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/pressable.dart';
import '../ui/segmented_control.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import '../ui/web_text_field.dart';
import 'recurring_actions.dart';
import 'recurring_model.dart';
import 'recurring_repository.dart';
import '../ui/lk_icons.dart';

/// The longest name a recurring payment has (the web's input `maxLength`).
const recurrenceNameMaxLength = 120;

enum _Kind { expense, income }

/// Opens the recurring payment's sheet: "Nuevo recurrente" when [editing] is null (it starts
/// [today]), else that payment's own values, with "Eliminar recurrente", which closes the sheet and
/// asks first (the web's page does, in its own sheet). [categories] are every category: the sheet
/// offers the active ones of the chosen kind, plus the edited payment's own, even archived since.
///
/// A refusal is said inside the sheet, which stays open with what was typed; a saved one closes it
/// and says so in a toast. Nothing is sent while a save is on its way.
Future<void> openRecurringForm(
  BuildContext context, {
  Recurrence? editing,
  required List<Category> categories,
  required String currency,
  required String today,
}) {
  final l10n = AppLocalizations.of(context);
  final form = _RecurringForm(
    editing: editing,
    categories: categories,
    currency: currency,
    today: today,
    l10n: l10n,
    actions: ProviderScope.containerOf(context).read(recurringActionsProvider),
    toasts: ToastHost.of(context),
    // The question needs the screen's own context, which outlives this sheet.
    onDelete: editing == null
        ? null
        : () {
            if (context.mounted) unawaited(openDeleteSheet(context, editing));
          },
  );
  return LkSheet.show<void>(
    context,
    title: editing == null ? l10n.recurringFormTitleNew : l10n.recurringFormTitleEdit,
    children: [_FormBody(form: form)],
    stuck: [_FormFooter(form: form)],
    stuckGaps: StuckGaps.recurring,
  ).whenComplete(form.dispose);
}

/// The delete question (the web's `ConfirmSheet` on the page): what deleting means, "Cancelar" and
/// "Sí, eliminar". A failure is said in a toast and the sheet stays for another try.
Future<bool> openDeleteSheet(BuildContext context, Recurrence rule) {
  final l10n = AppLocalizations.of(context);
  final actions = ProviderScope.containerOf(context).read(recurringActionsProvider);
  final toasts = ToastHost.of(context);
  return ConfirmSheet.show(
    context,
    title: l10n.recurringDeleteTitle(rule.name),
    body: l10n.recurringDeleteBody,
    confirmLabel: l10n.recurringDeleteConfirm,
    confirmKey: const Key('recurring.delete.confirm'),
    onConfirm: () async {
      try {
        await actions.remove(rule);
      } on HomeFailure catch (failure) {
        toasts.say(recurringFailureMessage(l10n, failure), error: true);
        rethrow;
      }
      toasts.say(l10n.recurringDeleted(rule.name));
    },
  );
}

/// What the sheet holds: the values, the error being shown, and whether a save is under way.
class _RecurringForm extends ChangeNotifier {
  _RecurringForm({
    required this.editing,
    required this.categories,
    required this.currency,
    required this.today,
    required this.l10n,
    required this.actions,
    required this.toasts,
    required this.onDelete,
  }) : name = TextEditingController(text: editing?.name ?? ''),
       nameFocus = FocusNode() {
    final rule = editing;
    final start = categories.where((c) => c.id == rule?.categoryId).firstOrNull;
    kind = switch (start?.kind) {
      CategoryKindEnum.income => _Kind.income,
      CategoryKindEnum.expense => _Kind.expense,
      _ => rule != null && rule.amount > 0 ? _Kind.income : _Kind.expense,
    };
    raw = rule == null ? '' : keypadText(rule.amount, l10n.localeName, currency);
    categoryId = rule?.categoryId;
    frequency = rule?.frequency ?? RecurrenceFrequencyEnum.monthly;
    day = rule?.dayOfMonth ?? int.parse(today.substring(8, 10));
    monthOfYear = rule?.monthOfYear;
    startDate = rule?.startDate ?? today;
    endDate = rule?.endDate ?? '';
    name.addListener(() {
      if (name.text == _name) return;
      _name = name.text;
      problem = null;
      notifyListeners();
    });
    _name = name.text;
  }

  final Recurrence? editing;
  final List<Category> categories;
  final String currency;
  final String today;
  final AppLocalizations l10n;
  final RecurringActions actions;
  final ToastController toasts;
  final VoidCallback? onDelete;

  final TextEditingController name;
  final FocusNode nameFocus;
  var _name = '';

  late _Kind kind;
  late String raw;
  String? categoryId;
  late RecurrenceFrequencyEnum frequency;
  late int day;
  int? monthOfYear;
  late String startDate;
  late String endDate;

  /// The first mistake of what was sent, by field (null: the server's refusal, or none), and what
  /// to say about it.
  RecurrenceField? problemField;
  String? problem;
  bool saving = false;
  bool _disposed = false;

  String get locale => l10n.localeName;
  AmountFormat get format => AmountFormat(locale, currency);
  int get cents => amountCents(raw, format);

  /// The categories to choose from: this kind's active ones, and the edited payment's own, even if
  /// archived since. In the categories' own order.
  List<Category> get choices {
    final ofKind = [
      for (final (index, c) in categories.indexed)
        if (c.kind == (kind == _Kind.income ? CategoryKindEnum.income : CategoryKindEnum.expense) &&
            (!c.archived || c.id == editing?.categoryId))
          (index, c),
    ];
    ofKind.sort((a, b) {
      final byOrder = a.$2.sortOrder.compareTo(b.$2.sortOrder);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    return [for (final (_, c) in ofKind) c];
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    name.dispose();
    nameFocus.dispose();
    super.dispose();
  }

  void _edit(void Function() change, {bool clearsProblem = true}) {
    change();
    if (clearsProblem) {
      problem = null;
      problemField = null;
    }
    notifyListeners();
  }

  void setRaw(String next) => _edit(() => raw = next);

  void changeKind(_Kind next) => _edit(() {
    kind = next;
    final chosen = categories.where((c) => c.id == categoryId).firstOrNull;
    final wanted = next == _Kind.income ? CategoryKindEnum.income : CategoryKindEnum.expense;
    if (chosen?.kind != wanted) categoryId = null;
  }, clearsProblem: false);

  void pickCategory(String id) => _edit(() => categoryId = id);
  void setFrequency(RecurrenceFrequencyEnum next) => _edit(() => frequency = next);
  void setDay(int next) => _edit(() => day = next, clearsProblem: false);
  void setMonth(int? next) => _edit(() => monthOfYear = next);
  void setStart(String next) => _edit(() => startDate = next);
  void setEnd(String next) => _edit(() => endDate = next);

  String _message(RecurrenceField field) => switch (field) {
    RecurrenceField.amount => l10n.recurringFormAmountRequired,
    RecurrenceField.name => l10n.recurringFormNameRequired,
    RecurrenceField.category => l10n.recurringFormCategoryRequired,
    RecurrenceField.month => l10n.recurringFormMonthRequired,
    RecurrenceField.start => l10n.recurringFormStartRequired,
    RecurrenceField.end => l10n.recurringFormEndBeforeStart,
  };

  Future<void> save(BuildContext context) async {
    if (saving) return;
    final field = recurrenceProblem(
      RecurrenceDraft(
        cents: cents,
        name: name.text,
        categoryId: categoryId,
        frequency: frequency,
        monthOfYear: monthOfYear,
        startDate: startDate,
        endDate: endDate,
      ),
    );
    if (field != null) {
      problemField = field;
      problem = _message(field);
      notifyListeners();
      return;
    }
    final values = NewRecurrence(
      name: name.text.trim(),
      amount: kind == _Kind.expense ? -cents : cents,
      categoryId: categoryId!,
      frequency: frequency,
      dayOfMonth: day,
      monthOfYear: frequency == RecurrenceFrequencyEnum.yearly ? monthOfYear : null,
      startDate: startDate,
      endDate: endDate.isEmpty ? null : endDate,
    );
    final navigator = Navigator.of(context);
    saving = true;
    problem = null;
    problemField = null;
    notifyListeners();
    try {
      final rule = editing;
      if (rule == null) {
        await actions.create(values);
      } else {
        await actions.save(rule, values);
      }
    } on HomeFailure catch (failure) {
      saving = false;
      problem = recurringFailureMessage(l10n, failure);
      notifyListeners();
      return;
    }
    // Closed meanwhile (a drag down): it was still saved, and it says so.
    if (!_disposed) {
      saving = false;
      navigator.pop();
    }
    toasts.say(l10n.recurringSaved(values.name));
  }

  /// "Eliminar recurrente": the sheet goes, and the question comes after it.
  void askToDelete(BuildContext context) {
    if (saving || onDelete == null) return;
    Navigator.of(context).pop();
    onDelete!();
  }
}

/// `<form noValidate className="flex flex-col gap-(--space-3) pt-(--space-2)">`.
class _FormBody extends StatefulWidget {
  const _FormBody({required this.form});

  final _RecurringForm form;

  @override
  State<_FormBody> createState() => _FormBodyState();
}

class _FormBodyState extends State<_FormBody> {
  final _errorKey = GlobalKey();
  String? _shown;

  _RecurringForm get form => widget.form;

  /// The message sits above the sticky footer, which could cover it: bring it into view.
  void _reveal() {
    final message = form.problem;
    if (message == _shown) return;
    _shown = message;
    if (message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _errorKey.currentContext;
      if (context != null && context.mounted) {
        unawaited(Scrollable.ensureVisible(context, duration: Duration.zero));
      }
    });
  }

  Future<void> _pickDay() async {
    final picked = await _choose<int>(
      context,
      title: form.l10n.recurringFormDayLabel,
      options: [for (var d = 1; d <= 31; d++) (d, '$d')],
      current: form.day,
    );
    if (picked != null) form.setDay(picked);
  }

  Future<void> _pickMonth() async {
    final picked = await _choose<int>(
      context,
      title: form.l10n.recurringFormMonthLabel,
      options: [
        for (var m = 1; m <= 12; m++)
          (m, formatMonthName('2026-${m.toString().padLeft(2, '0')}', form.locale)),
      ],
      current: form.monthOfYear,
    );
    if (picked != null) form.setMonth(picked);
  }

  Future<String?> _pickDate(String current, {String? first}) async {
    final from = DateTime.tryParse(current) ?? DateTime.tryParse(form.today)!;
    final firstDate = DateTime.tryParse(first ?? '') ?? DateTime(2000);
    final picked = await showDatePicker(
      context: context,
      initialDate: from.isBefore(firstDate) ? firstDate : from,
      firstDate: firstDate,
      lastDate: DateTime(2100),
    );
    if (picked == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${picked.year.toString().padLeft(4, '0')}-${two(picked.month)}-${two(picked.day)}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: form,
    builder: (context, _) {
      _reveal();
      final l10n = form.l10n;
      final colors = context.lkColors;
      final field = form.problemField;
      final yearly = form.frequency == RecurrenceFrequencyEnum.yearly;
      final choices = form.choices;
      return Padding(
        padding: const EdgeInsets.only(top: WambitoTokens.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space3,
          children: [
            SegmentedControl<_Kind>(
              label: l10n.recurringFormKindLabel,
              value: form.kind,
              onChanged: form.changeKind,
              options: [
                SegmentOption(
                  _Kind.expense,
                  l10n.recurringFormExpense,
                  key: const Key('recurring.kind.expense'),
                ),
                SegmentOption(
                  _Kind.income,
                  l10n.recurringFormIncome,
                  key: const Key('recurring.kind.income'),
                ),
              ],
            ),
            AmountField(
              raw: form.raw,
              onChanged: form.setRaw,
              currency: form.currency,
              sign: form.kind == _Kind.expense ? '−' : '+',
              tone: form.kind == _Kind.expense ? AmountTone.expense : AmountTone.income,
              invalid: field == RecurrenceField.amount,
              // `gap-(--space-3)` of the form sits between the figure and the keypad.
              gap: WambitoTokens.space3,
              // A phone up to 844 px tall: the tighter keys, as the budget sheet has.
              compact: MediaQuery.sizeOf(context).height < compactFooterBelow,
            ),
            FieldLabel(
              label: l10n.recurringFormNameLabel,
              child: WebTextField(
                controller: form.name,
                focusNode: form.nameFocus,
                fieldKey: const Key('recurring.name'),
                label: l10n.recurringFormNameLabel,
                placeholder: l10n.recurringFormNamePlaceholder,
                invalid: field == RecurrenceField.name,
                inputMinHeight: 24,
                inputFormatters: [LengthLimitingTextInputFormatter(recurrenceNameMaxLength)],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(form.save(context)),
              ),
            ),
            ExcludeSemantics(child: _Caption(l10n.recurringFormCategoryLabel)),
            if (choices.isEmpty)
              Text(
                form.kind == _Kind.income
                    ? l10n.recurringFormNoCategoriesIncome
                    : l10n.recurringFormNoCategoriesExpense,
                style: LkText.fieldLabel.copyWith(color: colors.inkMuted),
              )
            else
              Semantics(
                container: true,
                label: l10n.recurringFormCategoryLabel,
                child: CategoryChipGrid(
                  children: [
                    for (final c in choices)
                      CategoryChip(
                        key: Key('recurring.category.${c.id}'),
                        glyph: categoryLook(icon: c.icon, color: c.color).glyph,
                        label: c.name,
                        selected: form.categoryId == c.id,
                        onSelect: () => form.pickCategory(c.id),
                      ),
                  ],
                ),
              ),
            ExcludeSemantics(child: _Caption(l10n.recurringFormFrequencyLabel)),
            SegmentedControl<RecurrenceFrequencyEnum>(
              label: l10n.recurringFormFrequencyLabel,
              value: form.frequency,
              onChanged: form.setFrequency,
              options: [
                SegmentOption(
                  RecurrenceFrequencyEnum.monthly,
                  l10n.recurringFormMonthly,
                  key: const Key('recurring.frequency.monthly'),
                ),
                SegmentOption(
                  RecurrenceFrequencyEnum.yearly,
                  l10n.recurringFormYearly,
                  key: const Key('recurring.frequency.yearly'),
                ),
              ],
            ),
            _Grid2(
              first: FieldLabel(
                label: l10n.recurringFormDayLabel,
                child: _SelectBox(
                  key: const Key('recurring.day'),
                  label: l10n.recurringFormDayLabel,
                  text: '${form.day}',
                  onTap: _pickDay,
                ),
              ),
              second: yearly
                  ? FieldLabel(
                      label: l10n.recurringFormMonthLabel,
                      child: _SelectBox(
                        key: const Key('recurring.month'),
                        label: l10n.recurringFormMonthLabel,
                        text: form.monthOfYear == null
                            ? l10n.recurringFormMonthPlaceholder
                            : formatMonthName(
                                '2026-${form.monthOfYear.toString().padLeft(2, '0')}',
                                form.locale,
                              ),
                        placeholder: form.monthOfYear == null,
                        invalid: field == RecurrenceField.month,
                        onTap: _pickMonth,
                      ),
                    )
                  : null,
            ),
            if (form.day > 28)
              Text(
                l10n.recurringFormShortMonths,
                style: LkText.fieldLabel.copyWith(color: colors.inkMuted),
              ),
            _Grid2(
              first: DateField(
                key: const Key('recurring.start'),
                label: l10n.recurringFormStartLabel,
                date: form.startDate,
                locale: form.locale,
                invalid: field == RecurrenceField.start,
                onTap: () async {
                  final picked = await _pickDate(form.startDate);
                  if (picked != null) form.setStart(picked);
                },
              ),
              second: ClearableDate(
                clearLabel: l10n.recurringFormClearEnd,
                clearKey: const Key('recurring.end.clear'),
                onClear: form.endDate.isEmpty ? null : () => form.setEnd(''),
                child: DateField(
                  key: const Key('recurring.end'),
                  label: l10n.recurringFormEndLabel,
                  date: form.endDate,
                  locale: form.locale,
                  invalid: field == RecurrenceField.end,
                  onTap: () async {
                    final picked = await _pickDate(
                      form.endDate.isEmpty ? form.startDate : form.endDate,
                      first: form.startDate,
                    );
                    if (picked != null) form.setEnd(picked);
                  },
                ),
              ),
            ),
            if (form.problem != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  form.problem!,
                  key: _errorKey,
                  style: LkText.note.copyWith(color: colors.over),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// `text-[13px] font-bold text-ink-muted`: a caption over a group.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => BlinkLine(
    style: LkText.fieldLabel,
    child: Text(text, style: LkText.fieldLabel.copyWith(color: context.lkColors.inkMuted)),
  );
}

/// `grid grid-cols-2 gap-(--space-2)`: two equal columns; the second may be missing (the month of a
/// monthly rule), and the first keeps its half.
class _Grid2 extends StatelessWidget {
  const _Grid2({required this.first, this.second});

  final Widget first;
  final Widget? second;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: WambitoTokens.space2,
    children: [
      Expanded(child: first),
      Expanded(child: second ?? const SizedBox.shrink()),
    ],
  );
}

/// A `<select class="lk-input min-h-11">` closed: the chosen text in the field's box, with the
/// browser's little arrow after it. Tapping opens the choices.
class _SelectBox extends StatelessWidget {
  const _SelectBox({
    super.key,
    required this.label,
    required this.text,
    required this.onTap,
    this.placeholder = false,
    this.invalid = false,
  });

  final String label;
  final String text;
  final VoidCallback onTap;

  /// [text] is the "Elige un mes" prompt, not a value.
  final bool placeholder;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Pressable(
      onPressed: onTap,
      label: '$label, $text',
      builder: (context, state) => InputBox(
        focused: state.focusVisible,
        borderColor: invalid ? colors.over : null,
        child: Row(
          children: [
            Expanded(
              child: BlinkLine(
                style: LkText.input,
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LkText.input.copyWith(color: placeholder ? colors.inkMuted : colors.ink),
                ),
              ),
            ),
            const SizedBox(width: 4),
            ExcludeSemantics(
              child: CustomPaint(size: const Size(10, 6), painter: _ArrowPainter(colors.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small down arrow at the end of a closed select.
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(1, 1)
        ..lineTo(size.width / 2, size.height - 1)
        ..lineTo(size.width - 1, 1),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

/// The choices of a select, as a sheet: a list to tap, the current one ticked. Pops with the choice.
Future<T?> _choose<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T? current,
}) => LkSheet.show<T>(
  context,
  title: title,
  children: [
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (value, text) in options)
          _ChoiceRow(
            key: Key('recurring.choice.$value'),
            text: text,
            selected: value == current,
            onTap: () => Navigator.of(context).pop(value),
          ),
      ],
    ),
  ],
);

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({super.key, required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Pressable(
      onPressed: onTap,
      label: text,
      selected: selected,
      builder: (context, state) => RingBox(
        radius: state.focusVisible ? LkSurface.radius(LkRadius.md) : null,
        color: colors.focus,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WambitoTokens.space2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: LkText.copy.copyWith(
                      color: colors.ink,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
                if (selected) LkIcon(LkIconName.check, color: colors.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet's stuck footer: "Eliminar recurrente" when editing, and Guardar, which takes the rest
/// of the row and waits while the save is on its way.
class _FormFooter extends StatelessWidget {
  const _FormFooter({required this.form});

  final _RecurringForm form;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: form,
    builder: (context, _) {
      final colors = context.lkColors;
      final l10n = form.l10n;
      // `flex gap-2`: the buttons stretch to the tallest (the secondary one's border is 4px more).
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            if (form.editing != null)
              PressButton(
                key: const Key('recurring.delete'),
                tone: PressTone.secondary,
                horizontalPadding: WambitoTokens.space4,
                onPressed: form.saving ? null : () => form.askToDelete(context),
                child: Text(
                  LkText.upperCase(l10n.recurringFormDelete),
                  style: TextStyle(color: colors.over),
                ),
              ),
            Expanded(
              child: Semantics(
                container: true,
                child: PressButton.text(
                  l10n.recurringFormSave,
                  key: const Key('recurring.save'),
                  horizontalPadding: WambitoTokens.space4,
                  onPressed: form.saving ? null : () => unawaited(form.save(context)),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
