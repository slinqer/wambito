// The web's BudgetSheet (apps/web/app/features/categories/BudgetSheet.tsx): a category's budget
// from the month on screen on, on the shared keypad.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../add/keypad_input.dart';
import '../home/home_repository.dart';
import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../home/home_format.dart';
import '../ui/amount_field.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import 'category_detail_controller.dart';
import '../privacy/masked_money.dart';

/// What the budget sheet says when saving fails: the server's own words for the cases the web's
/// catalogue has (`errors.<code>`), and the generic ones otherwise.
String budgetFailureMessage(AppLocalizations l10n, HomeFailure failure) {
  if (failure.offline) return l10n.errorNetwork;
  if (failure.code == 'budget_category_not_expense') return l10n.budgetErrorNotExpense;
  if (failure.status == 404) return l10n.budgetErrorNotFound;
  if (failure.status == 422) return l10n.addErrorInvalid;
  return failure.status >= 500 ? l10n.errorInternal : l10n.errorGeneric;
}

/// Opens a category's budget sheet (`PUT /v1/categories/{id}/budget`): the amount on the shared
/// keypad (a keyboard and a paste type too; pesos take no decimals, with the lukas hint), starting
/// from [budget], the one in force in [month]; the budget applies from [month] on. A minus, typed
/// or pasted, is refused and never sent, and so is nothing: a budget is above zero.
///
/// A failed save is said inside the sheet, which stays open with what was typed, so the old budget
/// stays and a retry is one tap. A saved one closes the sheet, says so in a toast, and brings the
/// detail, home's Te quedan and the widget up to date.
Future<void> openBudgetSheet(
  BuildContext context, {
  required String categoryId,
  required String categoryName,
  required String month,
  required int? budget,
  required String currency,
}) {
  final l10n = AppLocalizations.of(context);
  final form = _BudgetForm(
    categoryId: categoryId,
    categoryName: categoryName,
    month: month,
    currency: currency,
    locale: l10n.localeName,
    l10n: l10n,
    container: ProviderScope.containerOf(context),
    toasts: ToastHost.of(context),
    initial: budget,
  );
  return LkSheet.show<void>(
    context,
    title: l10n.budgetSheetTitle(categoryName),
    children: [_BudgetBody(form: form)],
    stuck: [_SaveButton(form: form)],
  ).whenComplete(form.close);
}

/// What the sheet holds: the typed amount, the error being shown, and whether a save is under way.
class _BudgetForm extends ChangeNotifier {
  _BudgetForm({
    required this.categoryId,
    required this.categoryName,
    required this.month,
    required this.currency,
    required this.locale,
    required this.l10n,
    required this.container,
    required this.toasts,
    required int? initial,
  }) : raw = initial == null || initial == 0 ? '' : keypadText(initial, locale, currency);

  final String categoryId;
  final String categoryName;
  final String month;
  final String currency;
  final String locale;
  final AppLocalizations l10n;
  final ProviderContainer container;
  final ToastController toasts;

  String raw;
  String? error;
  bool saving = false;
  bool _closed = false;

  AmountFormat get format => AmountFormat(locale, currency);

  /// The sheet is gone: a save that answers late changes nothing more (the notifier itself stays
  /// valid while the sheet slides out).
  void close() => _closed = true;

  @override
  void notifyListeners() {
    if (!_closed) super.notifyListeners();
  }

  void setRaw(String next) {
    raw = next;
    error = null;
    notifyListeners();
  }

  void refuseNegative() {
    error = l10n.budgetSheetNegative;
    notifyListeners();
  }

  Future<void> save(BuildContext context) async {
    if (saving) return;
    final cents = amountCents(raw, format);
    if (cents <= 0) {
      error = l10n.budgetSheetZero;
      notifyListeners();
      return;
    }
    final navigator = Navigator.of(context);
    final hidden = hiddenAmountsOf(context);
    saving = true;
    notifyListeners();
    try {
      await container.read(categoryDetailProvider(categoryId).notifier).setBudget(cents);
    } on HomeFailure catch (failure) {
      saving = false;
      error = budgetFailureMessage(l10n, failure);
      notifyListeners();
      return;
    }
    // Closed meanwhile (a drag down): the budget was still saved, and it says so.
    if (!_closed) navigator.pop();
    final money = shownMoney(hidden, cents, currency, locale);
    final hint = hidden ? null : lukasHint(cents, locale, currency: currency);
    toasts.say(l10n.budgetSheetSaved(categoryName, hint == null ? money : '$money $hint'));
  }
}

/// `<form className="flex flex-col gap-(--space-2) pt-(--space-2)">`: where the budget applies from,
/// the amount on its keypad, and the error, if any.
class _BudgetBody extends StatelessWidget {
  const _BudgetBody({required this.form});

  final _BudgetForm form;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return ListenableBuilder(
      listenable: form,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(top: WambitoTokens.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            Text(
              form.l10n.budgetSheetFromMonth(monthInSentence(form.month, form.locale)),
              textAlign: TextAlign.center,
              style: LkText.bodySm.copyWith(color: colors.inkMuted),
            ),
            AmountField(
              raw: form.raw,
              onChanged: form.setRaw,
              currency: form.currency,
              invalid: form.error != null,
              onNegative: form.refuseNegative,
              // A phone up to 844 px tall gets the add sheet's tighter keys (still 44px targets), so
              // the keypad and Guardar fit without the keypad scrolling under the footer.
              compact: MediaQuery.sizeOf(context).height < compactFooterBelow,
            ),
            if (form.error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  form.error!,
                  key: const Key('budget.error'),
                  textAlign: TextAlign.center,
                  style: LkText.body.copyWith(color: colors.over),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Guardar presupuesto", the sheet's stuck footer: disabled while the save is on its way.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.form});

  final _BudgetForm form;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: form,
    builder: (context, _) => Semantics(
      container: true,
      child: PressButton.text(
        form.l10n.budgetSheetSave,
        key: const Key('budget.save'),
        onPressed: form.saving ? null : () => unawaited(form.save(context)),
      ),
    ),
  );
}
