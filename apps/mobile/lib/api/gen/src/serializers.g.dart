// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serializers.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers =
    (Serializers().toBuilder()
          ..add(AdminActionReason.serializer)
          ..add(AdminAuditEntry.serializer)
          ..add(AdminAuditPage.serializer)
          ..add(AdminDeleteUser.serializer)
          ..add(AdminEmailChange.serializer)
          ..add(AdminMe.serializer)
          ..add(AdminMetrics.serializer)
          ..add(AdminMetricsWeeklyInner.serializer)
          ..add(AdminUser.serializer)
          ..add(AdminUserAssistantsInner.serializer)
          ..add(AdminUserPasskeysInner.serializer)
          ..add(Assistant.serializer)
          ..add(AssistantList.serializer)
          ..add(CaptureResult.serializer)
          ..add(CaptureResultCategory.serializer)
          ..add(CaptureResultResultEnum.serializer)
          ..add(CaptureResultTransaction.serializer)
          ..add(CaptureResultTransactionCaptureSourceEnum.serializer)
          ..add(CaptureResultTransactionSource_Enum.serializer)
          ..add(CaptureResultTransactionStatusEnum.serializer)
          ..add(Category.serializer)
          ..add(CategoryKindEnum.serializer)
          ..add(CategoryReport.serializer)
          ..add(CategoryReportItemsInner.serializer)
          ..add(ClaimEmailSend.serializer)
          ..add(ClaimEmailVerify.serializer)
          ..add(ConfirmImport.serializer)
          ..add(CostOfLivingReport.serializer)
          ..add(CostOfLivingReportCategoriesInner.serializer)
          ..add(CostOfLivingReportCategoriesInnerTypeEnum.serializer)
          ..add(CreateCapture.serializer)
          ..add(CreateCaptureKindEnum.serializer)
          ..add(CreateCaptureSource_Enum.serializer)
          ..add(CreateCategory.serializer)
          ..add(CreateCategoryKindEnum.serializer)
          ..add(CreateRecurrence.serializer)
          ..add(CreateRecurrenceFrequencyEnum.serializer)
          ..add(CreateTransaction.serializer)
          ..add(CreateTransactionRepeat.serializer)
          ..add(CreateTransactionRepeatFrequencyEnum.serializer)
          ..add(CreateTransactionSource_Enum.serializer)
          ..add(CreateTransactionStatusEnum.serializer)
          ..add(CreateTransactionsBatch.serializer)
          ..add(DeleteTransactionsBatch.serializer)
          ..add(EmailChangeConfirm.serializer)
          ..add(FileImport.serializer)
          ..add(FileImportStatusEnum.serializer)
          ..add(ImportStats.serializer)
          ..add(ImportStatsAverageMonthlySpendingInner.serializer)
          ..add(ImportStatsAverageWindow.serializer)
          ..add(ImportStatsRejectedInner.serializer)
          ..add(KeyWrap.serializer)
          ..add(KeyWrapKindEnum.serializer)
          ..add(KeyWraps.serializer)
          ..add(PasskeyAssertion.serializer)
          ..add(PasskeyAssertionAuthenticatorAttachmentEnum.serializer)
          ..add(PasskeyAssertionResponse.serializer)
          ..add(PasskeyAssertionTypeEnum.serializer)
          ..add(PasskeyRequestOptions.serializer)
          ..add(PasskeyRequestOptionsAllowCredentialsInner.serializer)
          ..add(PasskeyRequestOptionsAllowCredentialsInnerTypeEnum.serializer)
          ..add(Problem.serializer)
          ..add(ProblemErrorsInner.serializer)
          ..add(Profile.serializer)
          ..add(PulledRecords.serializer)
          ..add(PushApplied.serializer)
          ..add(PushConflict.serializer)
          ..add(PushRecords.serializer)
          ..add(PushRejected.serializer)
          ..add(PushRejectedErrorEnum.serializer)
          ..add(PushResult.serializer)
          ..add(PushResults.serializer)
          ..add(PutKeyWrap.serializer)
          ..add(PutKeyWrapKindEnum.serializer)
          ..add(Recurrence.serializer)
          ..add(RecurrenceFrequencyEnum.serializer)
          ..add(ReviewTransactions.serializer)
          ..add(RotateKeys.serializer)
          ..add(RotatedKeyWrap.serializer)
          ..add(RotatedKeyWrapKindEnum.serializer)
          ..add(SetBudget.serializer)
          ..add(Summary.serializer)
          ..add(SummaryCategoriesInner.serializer)
          ..add(SummaryCategoriesInnerStateEnum.serializer)
          ..add(SyncChange.serializer)
          ..add(SyncChangeTypeEnum.serializer)
          ..add(SyncRecord.serializer)
          ..add(SyncRecordTypeEnum.serializer)
          ..add(Transaction.serializer)
          ..add(TransactionCaptureSourceEnum.serializer)
          ..add(TransactionList.serializer)
          ..add(TransactionPage.serializer)
          ..add(TransactionPageTotals.serializer)
          ..add(TransactionSource_Enum.serializer)
          ..add(TransactionStatusEnum.serializer)
          ..add(TransactionSuggestion.serializer)
          ..add(TransactionSuggestions.serializer)
          ..add(TrendReport.serializer)
          ..add(TrendReportMonthsInner.serializer)
          ..add(UpdateCategory.serializer)
          ..add(UpdateCategoryKindEnum.serializer)
          ..add(UpdateProfile.serializer)
          ..add(UpdateProfileCurrencyEnum.serializer)
          ..add(UpdateProfileLocaleEnum.serializer)
          ..add(UpdateProfileOnboardingCompletedEnum.serializer)
          ..add(UpdateRecurrence.serializer)
          ..add(UpdateRecurrenceFrequencyEnum.serializer)
          ..add(UpdateTransaction.serializer)
          ..add(UpdateTransactionNeedsReviewEnum.serializer)
          ..add(UpdateTransactionStatusEnum.serializer)
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(AdminAuditEntry)]),
            () => ListBuilder<AdminAuditEntry>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(AdminMetricsWeeklyInner)]),
            () => ListBuilder<AdminMetricsWeeklyInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(AdminUserPasskeysInner)]),
            () => ListBuilder<AdminUserPasskeysInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(AdminUserAssistantsInner)]),
            () => ListBuilder<AdminUserAssistantsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Assistant)]),
            () => ListBuilder<Assistant>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(CategoryReportItemsInner)]),
            () => ListBuilder<CategoryReportItemsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(CostOfLivingReportCategoriesInner)]),
            () => ListBuilder<CostOfLivingReportCategoriesInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(CreateTransaction)]),
            () => ListBuilder<CreateTransaction>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(KeyWrap)]),
            () => ListBuilder<KeyWrap>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [
              const FullType(PasskeyRequestOptionsAllowCredentialsInner),
            ]),
            () => ListBuilder<PasskeyRequestOptionsAllowCredentialsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, const [
              const FullType(String),
              const FullType.nullable(JsonObject),
            ]),
            () => MapBuilder<String, JsonObject?>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ProblemErrorsInner)]),
            () => ListBuilder<ProblemErrorsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(PushResult)]),
            () => ListBuilder<PushResult>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(RotatedKeyWrap)]),
            () => ListBuilder<RotatedKeyWrap>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ImportStatsRejectedInner)]),
            () => ListBuilder<ImportStatsRejectedInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [
              const FullType(ImportStatsAverageMonthlySpendingInner),
            ]),
            () => ListBuilder<ImportStatsAverageMonthlySpendingInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SummaryCategoriesInner)]),
            () => ListBuilder<SummaryCategoriesInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SyncChange)]),
            () => ListBuilder<SyncChange>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SyncRecord)]),
            () => ListBuilder<SyncRecord>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Transaction)]),
            () => ListBuilder<Transaction>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Transaction)]),
            () => ListBuilder<Transaction>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(TransactionSuggestion)]),
            () => ListBuilder<TransactionSuggestion>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(TrendReportMonthsInner)]),
            () => ListBuilder<TrendReportMonthsInner>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, const [const FullType(String), const FullType(String)]),
            () => MapBuilder<String, String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, const [
              const FullType(String),
              const FullType.nullable(JsonObject),
            ]),
            () => MapBuilder<String, JsonObject?>(),
          ))
        .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
