// The web's import page (apps/web/app/features/onboarding/ImportPage.tsx): "Trae tu historial" with
// the same sources, how-to, preview and confirm as the onboarding's step, ending with the budgets.
// An empty account takes the file's currency on confirm (the API does it atomically, and drops the
// budgets in the old currency, which the preview warns about); leaving before confirming changes
// nothing. After the import, the budgets are prefilled from the file's recent months and saved only
// with "Guardar presupuestos".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../add/add_sheet.dart';
import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../budgets/budgets_repository.dart';
import '../capture/capture_sheet.dart';
import '../home/category_look.dart';
import '../home/home_controller.dart';
import '../home/home_repository.dart' show HomeFailure;
import '../home/wambi_face.dart';
import '../home/shell_navigation.dart';
import '../l10n/app_localizations.dart';
import '../vault/preview.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/manage_page.dart';
import '../ui/press_button.dart';
import 'budget_input.dart';
import 'budgets_form.dart';
import 'import_failure.dart';
import 'import_flow.dart';
import 'import_panel.dart';
import 'import_state.dart';

/// Where the budgets are, after an import.
enum _Budgets { editing, saving, saved }

/// `/import`: bring a history from another app, reached from home's card and from Settings.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _scroll = ScrollController();
  final _budgetsHeading = GlobalKey();
  var _budgets = _Budgets.editing;
  HomeFailure? _error;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get _locale => AppLocalizations.of(context).localeName;

  /// The categories as the budget list shows them: active spending ones.
  List<Category> _spending(HomeData? data) => [
    for (final c in data?.categories.values ?? const <Category>[])
      if (c.kind == CategoryKindEnum.expense && !c.archived) c,
  ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The drafts, with the budgets already saved filling the fields the import didn't.
  Map<String, String> _withSaved(Map<String, String> drafts, List<Category> spending) {
    final merged = {...drafts};
    for (final c in spending) {
      final saved = c.currentBudget;
      if (merged[c.id] == null && saved != null && saved != 0) {
        merged[c.id] = draftFromCents(saved, _locale);
      }
    }
    return merged;
  }

  /// The budgets section takes the view once there is an import to act on.
  void _showBudgets() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _budgetsHeading.currentContext;
      if (!mounted || target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
        ),
      );
    });
  }

  Future<void> _save(List<Category> spending, Map<String, String> drafts, HomeData data) async {
    if (_budgets == _Budgets.saving) return;
    setState(() {
      _budgets = _Budgets.saving;
      _error = null;
    });
    final month = data.todayAt(ref.read(clockProvider)()).substring(0, 7);
    final repo = ref.read(budgetsRepositoryProvider);
    try {
      // From this month on: each valid amount that differs from what the category already has.
      // Empty fields write nothing.
      await Future.wait([
        for (final c in spending)
          () async {
            final int? amount;
            try {
              amount = parseBudgetInput(drafts[c.id] ?? '', _locale);
            } on InvalidAmountException {
              return;
            }
            if (amount == null || c.currentBudget == amount) return;
            await repo.setBudget(c.id, amount, month: month);
          }(),
      ]);
      await ref.read(homeProvider.notifier).budgetChanged();
      if (mounted) setState(() => _budgets = _Budgets.saved);
    } on Object catch (error) {
      final failure = error is HomeFailure ? error : const HomeFailure(0);
      if (failure.unauthorized) {
        unawaited(ref.read(sessionProvider.notifier).signOut(discardGuest: true));
      }
      if (mounted) {
        setState(() {
          _error = failure;
          _budgets = _Budgets.editing;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final flow = ref.watch(importFlowProvider);
    final notifier = ref.read(importFlowProvider.notifier);
    final home = ref.watch(homeProvider);
    final data = home.data;
    final phase = flow.phase;
    final preview = ref.watch(isPreviewProvider);

    ref.listen(importFlowProvider.select((s) => s.phase is ImportImported), (before, imported) {
      if (imported && before != true) _showBudgets();
    });

    final done = phase is ImportImported && !phase.retrying && phase.error == null;
    final spending = _spending(data);
    final withSaved = _withSaved(flow.drafts, spending);
    final locale = _locale;
    final invalid = spending.any((c) => readDraft(withSaved[c.id], locale) == invalidDraft);
    final currency = data?.currency ?? '';
    final basis = notifier.prefillBasis();
    final basisText = basis == null
        ? null
        : basis.withActivity
        ? l10n.importPrefillBasisActivity(basis.months)
        : l10n.importPrefillBasis(basis.months);

    return ManagePage(
      key: const Key('import.page'),
      // The web's bar marks Inicio on a path outside its sections (`sectionOf`).
      current: 'home',
      controller: _scroll,
      onAdd: () => unawaited(openAddSheet(context)),
      onMic: () => unawaited(openCapture(context, listen: true)),
      onNavigate: (to) => navigateFromShell(context, ref, to, current: 'import'),
      // The web's page has no back link: `pt-4`, then the title.
      header: null,
      top: WambitoTokens.space4,
      mainBottom: 0,
      children: [
        Row(
          spacing: WambitoTokens.space3,
          children: [
            // The web's `<span className="shrink-0">` holds the face as an inline box: 7px of line
            // (the baseline's descent) under it make the row 79px tall.
            const SizedBox(
              width: 72,
              height: 79,
              child: Align(
                alignment: Alignment.topLeft,
                child: WambiFace(mood: WambiMood.happy, size: 72, decorative: true),
              ),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l10n.importPageTitle,
                  style: LkText.pageTitle.copyWith(color: colors.ink, fontSize: 26, height: 1.25),
                ),
              ),
            ),
          ],
        ),
        // The import is the server's (`POST /v1/imports`); an encrypted account's data is on the
        // phone, so the page says it waits for encryption and offers no picker.
        if (preview) const ComingSoonNotice(key: Key('import.comingSoon')),
        if (!preview && phase is ImportSources)
          Text(l10n.importPageLead, style: LkText.copy.copyWith(color: colors.inkMuted)),
        if (!preview)
          ImportPanel(
            state: phase,
            onChoose: () => unawaited(notifier.chooseFile()),
            onDiscard: () => unawaited(notifier.discard()),
            onSource: ({required budge}) => notifier.chooseSource(budge: budge),
            onRetry: () => notifier.retry(locale),
            onConfirm: () => unawaited(notifier.confirm(locale)),
            showPrefill: false,
          ),
        if (done && !preview)
          Column(
            key: const Key('import.budgets'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space3,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.importPageBudgetsTitle,
                  key: _budgetsHeading,
                  style: LkText.sectionTitle.copyWith(fontSize: 22, height: 1.5, color: colors.ink),
                ),
              ),
              if (_budgets == _Budgets.saved)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.importBudgetsSaved,
                    key: const Key('import.budgets.saved'),
                    style: LkText.sectionTitle.copyWith(
                      fontSize: 18,
                      height: 1.5,
                      color: colors.good,
                    ),
                  ),
                )
              else ...[
                Text(
                  l10n.importPageBudgetsLead,
                  style: LkText.copy.copyWith(color: colors.inkMuted),
                ),
                if (basisText != null)
                  Text(basisText, style: LkText.note.copyWith(color: colors.inkMuted)),
                BudgetsList(
                  categories: [
                    for (final c in spending)
                      () {
                        final look = categoryLook(icon: c.icon, color: c.color);
                        return BudgetCategory(
                          id: c.id,
                          name: c.name,
                          glyph: look.glyph,
                          tint: look.tint,
                        );
                      }(),
                  ],
                  drafts: withSaved,
                  onChange: (id, text) =>
                      notifier.replaceDrafts({...withSaved, ...flow.drafts, id: text}),
                  currency: currency,
                ),
                BudgetsTotal(
                  total: draftsTotal([for (final c in spending) c.id], withSaved, locale),
                  currency: currency,
                ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      importFailureMessage(l10n, _error!),
                      key: const Key('import.budgets.error'),
                      style: LkText.note.copyWith(color: colors.over),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: PressButton.text(
                    _budgets == _Budgets.saving ? l10n.importSavingBudgets : l10n.importSaveBudgets,
                    key: const Key('import.budgets.save'),
                    onPressed: invalid || _budgets == _Budgets.saving || data == null
                        ? null
                        : () => unawaited(_save(spending, withSaved, data)),
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: PressButton.text(
                  l10n.importGoHome,
                  key: const Key('import.home'),
                  tone: _budgets == _Budgets.saved ? PressTone.primary : PressTone.secondary,
                  link: true,
                  onPressed: () => navigateFromShell(context, ref, 'home', current: 'import'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
