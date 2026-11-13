// `/welcome/:step?`: the onboarding a new user sees once (the web's Welcome,
// apps/web/app/features/onboarding/Welcome.tsx, and its route, routes/welcome.tsx). It is optional
// and short: the welcome offers "Configurar en 1 minuto" or "Entrar directo", and every setup step
// has SIGUIENTE (apply what is on screen) and SALTAR (move on with this step's defaults).
//
// Who sees it is the session's to say (`sessionRedirect`, lib/router.dart): an account with no
// `onboardingCompletedAt` is sent here from every screen until it finishes, and one that has it, and
// a guest, never are. Finishing or skipping marks it done and the session sends the person home.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/category_look.dart';
import '../home/home_controller.dart';
import '../home/screen_error.dart';
import '../import/budgets_form.dart';
import '../import/import_flow.dart';
import '../l10n/app_localizations.dart';
import '../vault/preview.dart';
import '../ui/app_shell.dart';
import 'budgets_step.dart';
import 'categories_step.dart';
import 'currency_step.dart';
import 'import_step.dart';
import 'steps.dart';
import 'welcome_controller.dart';
import 'welcome_failure.dart';
import 'welcome_step.dart';

/// The welcome at [step], the step in the address (null for the first). The state of the welcome is
/// kept while this screen is: moving between steps changes only the address's step.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.step});

  final String? step;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The budgets are seeded in the app's language, so `300,50` is never read back as an English
    // 30050. Told after the frame: a provider is not changed while the tree is built.
    final locale = AppLocalizations.of(context).localeName;
    scheduleMicrotask(() {
      if (mounted) ref.read(welcomeProvider.notifier).useLocale(locale);
    });
  }

  void _go(StepId to) {
    ref.read(welcomeProvider.notifier).clearError();
    context.go(stepPath(to));
  }

  /// Back goes to the step before (never from the first, nor while something is being written).
  bool _canGoBack(StepId step, WelcomeState state, ImportFlowState flow) {
    final back = previousStep(step);
    return back != null && back != StepId.welcome && !state.busy && !flow.locked;
  }

  Widget _blank() => const PageBackground(
    key: Key('welcome.page'),
    child: Scaffold(backgroundColor: Colors.transparent, body: SizedBox.expand()),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final step = stepFromParam(widget.step);
    final state = ref.watch(welcomeProvider);
    final flow = ref.watch(importFlowProvider);
    final home = ref.watch(homeProvider);
    final controller = ref.read(welcomeProvider.notifier);
    final flowNotifier = ref.read(importFlowProvider.notifier);

    // An address that is none of the steps is the first.
    if (step == null) {
      scheduleMicrotask(() {
        if (mounted) context.go(stepPath(StepId.welcome));
      });
      return _blank();
    }

    // Only a first load that failed shows the error: a failed refresh keeps what is on screen.
    final failure = state.loadFailure ?? (home.data == null ? home.failure : null);
    if (failure != null) {
      return PageBackground(
        key: const Key('welcome.page'),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ScreenError(
            message: failure.offline ? l10n.errorNetwork : l10n.errorGeneric,
            retryLabel: l10n.retry,
            onRetry: () {
              if (state.loadFailure != null) controller.retryStart();
              unawaited(ref.read(homeProvider.notifier).refresh());
            },
          ),
        ),
      );
    }
    final data = home.data;
    if (data == null || !state.ready) return _blank();

    final spending = controller.spending;
    // A deep link (or a restart) to the budgets before any categories exist goes to make them
    // first. After the categories step it stays: deselecting everything is allowed.
    if (step == StepId.budgets && spending.isEmpty && !state.draft!.categoriesDone) {
      scheduleMicrotask(() {
        if (mounted) context.go(stepPath(StepId.categories));
      });
      return _blank();
    }

    final locale = l10n.localeName;
    final before = previousStep(step);
    final onBack = before != null && before != StepId.welcome ? () => _go(before) : null;
    final error = state.error == null ? null : welcomeFailureMessage(l10n, state.error!);

    final Widget content = switch (step) {
      StepId.welcome => WelcomeStep(
        key: const Key('welcome.step.welcome'),
        currency: state.currency!,
        onSetup: () => _go(StepId.currency),
        onDirect: () => unawaited(controller.enterDirectly()),
        busy: state.busy,
        error: error,
      ),
      StepId.currency => CurrencyStep(
        key: const Key('welcome.step.currency'),
        value: state.currency!,
        onChange: controller.chooseCurrency,
        onBack: onBack,
        busy: state.busy,
        error: error,
        onSkip: () => unawaited(
          controller.skipCurrency().then((went) {
            if (went && mounted) _go(StepId.import);
          }),
        ),
        onNext: () => unawaited(
          controller.saveCurrency().then((went) {
            if (went && mounted) _go(StepId.import);
          }),
        ),
      ),
      StepId.import => ImportStep(
        key: const Key('welcome.step.import'),
        state: flow.phase,
        onChoose: () => unawaited(flowNotifier.chooseFile()),
        onConfirm: () => unawaited(flowNotifier.confirm(locale)),
        onDiscard: () => unawaited(flowNotifier.discard()),
        onSource: ({required budge}) => flowNotifier.chooseSource(budge: budge),
        onRetry: () => flowNotifier.retry(locale),
        prefillBasis: _prefillBasis(l10n, flowNotifier),
        onBack: onBack,
        busy: state.busy,
        locked: flow.locked,
        preview: ref.watch(isPreviewProvider),
        onSkip: () => unawaited(
          controller.skipImport().then((left) {
            if (left && mounted) _go(StepId.categories);
          }),
        ),
        onNext: () => _go(StepId.categories),
      ),
      StepId.categories => CategoriesStep(
        key: const Key('welcome.step.categories'),
        chips: controller.chips,
        selected: state.selected!,
        onToggle: controller.toggle,
        notice: state.notice,
        onCreate: controller.create,
        onEdit: controller.edit,
        onRemove: controller.remove,
        transactionsOf: controller.transactionsOf,
        errorText: (problem) => welcomeFailureMessage(l10n, problem),
        onBack: onBack,
        busy: state.busy,
        error: error,
        onSkip: () => unawaited(
          controller.skipCategories().then((went) {
            if (went && mounted) _go(StepId.budgets);
          }),
        ),
        onNext: () => unawaited(
          controller.saveCategories().then((went) {
            if (went && mounted) _go(StepId.budgets);
          }),
        ),
      ),
      StepId.budgets => BudgetsStep(
        key: const Key('welcome.step.budgets'),
        categories: [
          for (final c in spending)
            () {
              final look = categoryLook(icon: c.icon, color: c.color);
              return BudgetCategory(id: c.id, name: c.name, glyph: look.glyph, tint: look.tint);
            }(),
        ],
        drafts: flow.drafts,
        onChange: flowNotifier.setDraft,
        currency: data.currency,
        prefillBasis: _prefillBasis(l10n, flowNotifier),
        error: error,
        onBack: onBack,
        busy: state.busy,
        onSkip: () => unawaited(controller.skipBudgets()),
        onNext: () => unawaited(controller.finish()),
      ),
    };

    // The system's back does what the screen's does: to the step before (from the first, or while
    // something is being written, it is the app's to handle, which leaves). The screen is not a
    // route of its own (one holds every step), so its back button is heard through the router.
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (before == null || before == StepId.welcome) return false;
        if (_canGoBack(step, state, flow)) _go(before);
        return true;
      },
      child: KeyedSubtree(key: const Key('welcome.page'), child: content),
    );
  }

  /// "Basado en lo que gastaste en tus últimos 3 meses", or "…con movimientos" for an old export.
  String? _prefillBasis(AppLocalizations l10n, ImportFlow flow) {
    final basis = flow.prefillBasis();
    if (basis == null) return null;
    return basis.withActivity
        ? l10n.importPrefillBasisActivity(basis.months)
        : l10n.importPrefillBasis(basis.months);
  }
}
