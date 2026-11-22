import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../feedback/feedback.dart';
import '../home/home_controller.dart';
import '../home/home_repository.dart';
import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../offline/pending_saves.dart';
import '../recurring/recurring_repository.dart';
import '../review/review_controller.dart';
import '../ui/toast.dart';
import 'add_form.dart';

/// What follows a save, apart from the sheet itself: when sending the same request again can work,
/// the words for a failure, and the toast with Deshacer (the web's `useTransactionActions`).

/// Whether sending the same request again can work: no answer at all (offline, a lost
/// connection), a server error or timeout, too many requests, the first try still running, or a
/// `preview` account's vault not open yet (423 `vault_locked`, lib/vault/finance_guard.dart: it
/// opens once unlocked, and a save waiting for it is never dropped). Not a refusal (a 4xx such as
/// an invalid amount), which says the same every time.
bool canRetrySave(HomeFailure failure) =>
    failure.status == 0 ||
    failure.status >= 500 ||
    failure.status == 408 ||
    failure.status == 429 ||
    failure.code == 'idempotency_in_progress' ||
    (failure.status == 423 && failure.code == 'vault_locked');

/// What the sheet says when a save fails.
String saveFailureMessage(AppLocalizations l10n, HomeFailure failure) {
  if (failure.offline) return l10n.errorNetwork;
  if (failure.code == 'idempotency_in_progress') return l10n.addErrorBusy;
  if (failure.code == 'category_not_found') return l10n.addErrorCategory;
  if (failure.status == 404) return l10n.addErrorNotFound;
  if (failure.status == 422) return l10n.addErrorInvalid;
  return failure.status >= 500 ? l10n.errorInternal : l10n.errorGeneric;
}

/// The toast after a new movement: what was saved, Deshacer (which takes it away again) and, for
/// a movement saved without a name, "Ponerle nombre" (which opens it on its name). Everything it
/// needs is passed in: the sheet is gone by the time anyone taps.
void toastCreated({
  required ProviderContainer container,
  required ToastController toasts,
  required NavigatorState navigator,
  required AppLocalizations l10n,
  required Transaction created,
  required Kind kind,
  required String categoryName,
  required String currency,
  required bool unnamed,
  required Future<void> Function(BuildContext context, Transaction tx) nameIt,
}) {
  final locale = l10n.localeName;
  final amount = formatMoney(created.amount.abs(), currency, locale);
  final hint = lukasHint(created.amount, locale, currency: currency);
  final line = kind == Kind.income
      ? l10n.addSavedIncome(categoryName, amount)
      : l10n.addSavedExpense(categoryName, amount);
  toasts.say(
    hint == null ? line : '$line $hint',
    actionLabel: l10n.undo,
    onAction: () => unawaited(_undoCreated(container, toasts, l10n, created)),
    extraLabel: unnamed ? l10n.addNameIt : null,
    onExtra: unnamed
        ? () {
            if (navigator.mounted) unawaited(nameIt(navigator.context, created));
          }
        : null,
  );
}

Future<void> _undoCreated(
  ProviderContainer container,
  ToastController toasts,
  AppLocalizations l10n,
  Transaction created,
) async {
  try {
    await container.read(homeProvider.notifier).remove(created);
    // Saved with "Repetir": the recurrence it made goes too (the movement is already deleted, so
    // only the pending ones it made after it go with it).
    final rule = created.recurrenceId;
    if (rule != null) await container.read(recurringRepositoryProvider).delete(rule);
  } on HomeFailure catch (failure) {
    toasts.say(failure.offline ? l10n.errorNetwork : l10n.errorGeneric, error: true);
    return;
  }
  container.read(feedbackProvider)(FeedbackEvent.undo);
  toasts.say(l10n.addUndone(created.name));
}

/// Eliminar on an edited movement: it goes at once (home does the same for a swipe) and the toast
/// offers Deshacer, which brings it back (the web's `actions.remove` and `bringBack`). The sheet is
/// gone by then, so everything it needs is passed in.
Future<void> deleteMovement({
  required ProviderContainer container,
  required ToastController toasts,
  required AppLocalizations l10n,
  required Transaction transaction,
}) async {
  if (isUnsent(transaction)) {
    final uploaded = await deleteUnsent(
      container: container,
      toasts: toasts,
      l10n: l10n,
      transaction: transaction,
    );
    if (uploaded == null) return;
    transaction = uploaded;
  }
  final home = container.read(homeProvider.notifier);
  container.read(feedbackProvider)(FeedbackEvent.deleted);
  try {
    await home.remove(transaction);
  } on HomeFailure catch (failure) {
    toasts.say(failure.offline ? l10n.errorNetwork : l10n.errorGeneric, error: true);
    return;
  }
  if (transaction.needsReview) container.invalidate(reviewProvider);
  toasts.say(
    l10n.transactionDeleted(transaction.name),
    actionLabel: l10n.undo,
    onAction: () => unawaited(_bringBack(container, toasts, l10n, transaction)),
  );
}

Future<void> _bringBack(
  ProviderContainer container,
  ToastController toasts,
  AppLocalizations l10n,
  Transaction transaction,
) async {
  try {
    await container.read(homeProvider.notifier).restore(transaction);
  } on HomeFailure catch (failure) {
    toasts.say(failure.offline ? l10n.errorNetwork : l10n.errorGeneric, error: true);
    return;
  }
  if (transaction.needsReview) container.invalidate(reviewProvider);
  container.read(feedbackProvider)(FeedbackEvent.undo);
  toasts.say(l10n.transactionRestored(transaction.name));
}

/// The row [transaction] stood for, as the server has it, when it was not uploaded yet but is by
/// now (the sheet or the swipe started before it went up). Null when the server's id is not known.
Transaction? uploadedRow(ProviderContainer container, Transaction transaction) {
  final id = container.read(pendingSavesProvider.notifier).uploadedId(transaction.id);
  return id == null ? null : transaction.rebuild((b) => b.id = id);
}

/// Eliminar on a row not uploaded yet: it goes at once, with Deshacer on the toast, and the server
/// deletes the movement once it has it. When the row went up meanwhile, answers it as the server
/// has it, for the caller to delete there (null when there is nothing more to do).
Future<Transaction?> deleteUnsent({
  required ProviderContainer container,
  required ToastController toasts,
  required AppLocalizations l10n,
  required Transaction transaction,
}) async {
  final queue = container.read(pendingSavesProvider.notifier);
  if (await queue.remove(transaction.id)) {
    container.read(feedbackProvider)(FeedbackEvent.deleted);
    toasts.say(
      l10n.transactionDeleted(transaction.name),
      actionLabel: l10n.undo,
      onAction: () => unawaited(_bringBackUnsent(container, toasts, l10n, transaction)),
    );
    return null;
  }
  final uploaded = uploadedRow(container, transaction);
  if (uploaded == null) toasts.say(l10n.errorGeneric, error: true);
  return uploaded;
}

Future<void> _bringBackUnsent(
  ProviderContainer container,
  ToastController toasts,
  AppLocalizations l10n,
  Transaction transaction,
) async {
  final bool back;
  try {
    back = await container.read(pendingSavesProvider.notifier).restore(transaction.id);
  } on HomeFailure catch (failure) {
    toasts.say(failure.offline ? l10n.errorNetwork : l10n.errorGeneric, error: true);
    return;
  }
  if (!back) {
    // It went up, deleted, meanwhile: the server brings it back.
    final uploaded = uploadedRow(container, transaction);
    if (uploaded == null) {
      toasts.say(l10n.errorGeneric, error: true);
      return;
    }
    await _bringBack(container, toasts, l10n, uploaded);
    return;
  }
  container.read(feedbackProvider)(FeedbackEvent.undo);
  toasts.say(l10n.transactionRestored(transaction.name));
}
