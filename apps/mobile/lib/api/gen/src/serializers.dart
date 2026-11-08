//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:wambito/api/gen/src/date_serializer.dart';
import 'package:wambito/api/gen/src/model/date.dart';

import 'package:wambito/api/gen/src/model/admin_action_reason.dart';
import 'package:wambito/api/gen/src/model/admin_audit_entry.dart';
import 'package:wambito/api/gen/src/model/admin_audit_page.dart';
import 'package:wambito/api/gen/src/model/admin_delete_user.dart';
import 'package:wambito/api/gen/src/model/admin_email_change.dart';
import 'package:wambito/api/gen/src/model/admin_me.dart';
import 'package:wambito/api/gen/src/model/admin_metrics.dart';
import 'package:wambito/api/gen/src/model/admin_metrics_weekly_inner.dart';
import 'package:wambito/api/gen/src/model/admin_user.dart';
import 'package:wambito/api/gen/src/model/admin_user_assistants_inner.dart';
import 'package:wambito/api/gen/src/model/admin_user_passkeys_inner.dart';
import 'package:wambito/api/gen/src/model/assistant.dart';
import 'package:wambito/api/gen/src/model/assistant_list.dart';
import 'package:wambito/api/gen/src/model/capture_result.dart';
import 'package:wambito/api/gen/src/model/capture_result_category.dart';
import 'package:wambito/api/gen/src/model/capture_result_transaction.dart';
import 'package:wambito/api/gen/src/model/category.dart';
import 'package:wambito/api/gen/src/model/category_report.dart';
import 'package:wambito/api/gen/src/model/category_report_items_inner.dart';
import 'package:wambito/api/gen/src/model/claim_email_send.dart';
import 'package:wambito/api/gen/src/model/claim_email_verify.dart';
import 'package:wambito/api/gen/src/model/confirm_import.dart';
import 'package:wambito/api/gen/src/model/cost_of_living_report.dart';
import 'package:wambito/api/gen/src/model/cost_of_living_report_categories_inner.dart';
import 'package:wambito/api/gen/src/model/create_capture.dart';
import 'package:wambito/api/gen/src/model/create_category.dart';
import 'package:wambito/api/gen/src/model/create_recurrence.dart';
import 'package:wambito/api/gen/src/model/create_transaction.dart';
import 'package:wambito/api/gen/src/model/create_transaction_repeat.dart';
import 'package:wambito/api/gen/src/model/create_transactions_batch.dart';
import 'package:wambito/api/gen/src/model/delete_transactions_batch.dart';
import 'package:wambito/api/gen/src/model/email_change_confirm.dart';
import 'package:wambito/api/gen/src/model/file_import.dart';
import 'package:wambito/api/gen/src/model/import_stats.dart';
import 'package:wambito/api/gen/src/model/import_stats_average_monthly_spending_inner.dart';
import 'package:wambito/api/gen/src/model/import_stats_average_window.dart';
import 'package:wambito/api/gen/src/model/import_stats_rejected_inner.dart';
import 'package:wambito/api/gen/src/model/key_wrap.dart';
import 'package:wambito/api/gen/src/model/key_wraps.dart';
import 'package:wambito/api/gen/src/model/pairing_approver.dart';
import 'package:wambito/api/gen/src/model/pairing_found.dart';
import 'package:wambito/api/gen/src/model/pairing_pickup.dart';
import 'package:wambito/api/gen/src/model/pairing_reveal.dart';
import 'package:wambito/api/gen/src/model/pairing_started.dart';
import 'package:wambito/api/gen/src/model/pairing_state.dart';
import 'package:wambito/api/gen/src/model/passkey_assertion.dart';
import 'package:wambito/api/gen/src/model/passkey_assertion_response.dart';
import 'package:wambito/api/gen/src/model/passkey_request_options.dart';
import 'package:wambito/api/gen/src/model/passkey_request_options_allow_credentials_inner.dart';
import 'package:wambito/api/gen/src/model/problem.dart';
import 'package:wambito/api/gen/src/model/problem_errors_inner.dart';
import 'package:wambito/api/gen/src/model/profile.dart';
import 'package:wambito/api/gen/src/model/pulled_records.dart';
import 'package:wambito/api/gen/src/model/push_applied.dart';
import 'package:wambito/api/gen/src/model/push_conflict.dart';
import 'package:wambito/api/gen/src/model/push_records.dart';
import 'package:wambito/api/gen/src/model/push_rejected.dart';
import 'package:wambito/api/gen/src/model/push_result.dart';
import 'package:wambito/api/gen/src/model/push_results.dart';
import 'package:wambito/api/gen/src/model/put_key_wrap.dart';
import 'package:wambito/api/gen/src/model/recurrence.dart';
import 'package:wambito/api/gen/src/model/review_transactions.dart';
import 'package:wambito/api/gen/src/model/rotate_keys.dart';
import 'package:wambito/api/gen/src/model/rotated_key_wrap.dart';
import 'package:wambito/api/gen/src/model/seal_pairing.dart';
import 'package:wambito/api/gen/src/model/set_budget.dart';
import 'package:wambito/api/gen/src/model/start_pairing.dart';
import 'package:wambito/api/gen/src/model/summary.dart';
import 'package:wambito/api/gen/src/model/summary_categories_inner.dart';
import 'package:wambito/api/gen/src/model/sync_change.dart';
import 'package:wambito/api/gen/src/model/sync_record.dart';
import 'package:wambito/api/gen/src/model/transaction.dart';
import 'package:wambito/api/gen/src/model/transaction_list.dart';
import 'package:wambito/api/gen/src/model/transaction_page.dart';
import 'package:wambito/api/gen/src/model/transaction_page_totals.dart';
import 'package:wambito/api/gen/src/model/transaction_suggestion.dart';
import 'package:wambito/api/gen/src/model/transaction_suggestions.dart';
import 'package:wambito/api/gen/src/model/trend_report.dart';
import 'package:wambito/api/gen/src/model/trend_report_months_inner.dart';
import 'package:wambito/api/gen/src/model/update_category.dart';
import 'package:wambito/api/gen/src/model/update_profile.dart';
import 'package:wambito/api/gen/src/model/update_recurrence.dart';
import 'package:wambito/api/gen/src/model/update_transaction.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminActionReason,
  AdminAuditEntry,
  AdminAuditPage,
  AdminDeleteUser,
  AdminEmailChange,
  AdminMe,
  AdminMetrics,
  AdminMetricsWeeklyInner,
  AdminUser,
  AdminUserAssistantsInner,
  AdminUserPasskeysInner,
  Assistant,
  AssistantList,
  CaptureResult,
  CaptureResultCategory,
  CaptureResultTransaction,
  Category,
  CategoryReport,
  CategoryReportItemsInner,
  ClaimEmailSend,
  ClaimEmailVerify,
  ConfirmImport,
  CostOfLivingReport,
  CostOfLivingReportCategoriesInner,
  CreateCapture,
  CreateCategory,
  CreateRecurrence,
  CreateTransaction,
  CreateTransactionRepeat,
  CreateTransactionsBatch,
  DeleteTransactionsBatch,
  EmailChangeConfirm,
  FileImport,
  ImportStats,
  ImportStatsAverageMonthlySpendingInner,
  ImportStatsAverageWindow,
  ImportStatsRejectedInner,
  KeyWrap,
  KeyWraps,
  PairingApprover,
  PairingFound,
  PairingPickup,
  PairingReveal,
  PairingStarted,
  PairingState,
  PasskeyAssertion,
  PasskeyAssertionResponse,
  PasskeyRequestOptions,
  PasskeyRequestOptionsAllowCredentialsInner,
  Problem,
  ProblemErrorsInner,
  Profile,
  PulledRecords,
  PushApplied,
  PushConflict,
  PushRecords,
  PushRejected,
  PushResult,
  PushResults,
  PutKeyWrap,
  Recurrence,
  ReviewTransactions,
  RotateKeys,
  RotatedKeyWrap,
  SealPairing,
  SetBudget,
  StartPairing,
  Summary,
  SummaryCategoriesInner,
  SyncChange,
  SyncRecord,
  Transaction,
  TransactionList,
  TransactionPage,
  TransactionPageTotals,
  TransactionSuggestion,
  TransactionSuggestions,
  TrendReport,
  TrendReportMonthsInner,
  UpdateCategory,
  UpdateProfile,
  UpdateRecurrence,
  UpdateTransaction,
])
Serializers serializers =
    (_$serializers.toBuilder()
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(RotatedKeyWrap)]),
            () => ListBuilder<RotatedKeyWrap>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, [FullType(String), FullType(String)]),
            () => MapBuilder<String, String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(PushResult)]),
            () => ListBuilder<PushResult>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(ProblemErrorsInner)]),
            () => ListBuilder<ProblemErrorsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(SyncChange)]),
            () => ListBuilder<SyncChange>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(Transaction)]),
            () => ListBuilder<Transaction>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(AdminUserPasskeysInner)]),
            () => ListBuilder<AdminUserPasskeysInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(TransactionSuggestion)]),
            () => ListBuilder<TransactionSuggestion>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(CostOfLivingReportCategoriesInner)]),
            () => ListBuilder<CostOfLivingReportCategoriesInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(KeyWrap)]),
            () => ListBuilder<KeyWrap>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(SyncRecord)]),
            () => ListBuilder<SyncRecord>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(PasskeyRequestOptionsAllowCredentialsInner)]),
            () => ListBuilder<PasskeyRequestOptionsAllowCredentialsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(CategoryReportItemsInner)]),
            () => ListBuilder<CategoryReportItemsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(TrendReportMonthsInner)]),
            () => ListBuilder<TrendReportMonthsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(Recurrence)]),
            () => ListBuilder<Recurrence>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(AdminMetricsWeeklyInner)]),
            () => ListBuilder<AdminMetricsWeeklyInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(Category)]),
            () => ListBuilder<Category>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(SummaryCategoriesInner)]),
            () => ListBuilder<SummaryCategoriesInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
            () => MapBuilder<String, JsonObject?>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(AdminUserAssistantsInner)]),
            () => ListBuilder<AdminUserAssistantsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(CreateTransaction)]),
            () => ListBuilder<CreateTransaction>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(AdminAuditEntry)]),
            () => ListBuilder<AdminAuditEntry>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(ImportStatsRejectedInner)]),
            () => ListBuilder<ImportStatsRejectedInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(Assistant)]),
            () => ListBuilder<Assistant>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, [FullType(ImportStatsAverageMonthlySpendingInner)]),
            () => ListBuilder<ImportStatsAverageMonthlySpendingInner>(),
          )
          ..add(const OneOfSerializer())
          ..add(const AnyOfSerializer())
          ..add(const DateSerializer())
          ..add(Iso8601DateTimeSerializer()))
        .build();

Serializers standardSerializers = (serializers.toBuilder()..addPlugin(StandardJsonPlugin()))
    .build();
