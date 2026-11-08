import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../home/home_repository.dart';

/// What the budgets screens read and change on the server, as the web's queries do
/// (apps/web/app/api/queries.ts): a category's movements in a month, what came in to an income
/// category, and a category's budget. The month's summary, the categories and the profile are
/// home's ([HomeRepository]).
abstract interface class BudgetsRepository {
  /// One category's movements in [month] (`YYYY-MM`), newest first, a page at a time
  /// (`useCategoryTransactions`).
  Future<TransactionsPage> categoryTransactions(String month, String categoryId, {String? cursor});

  /// What came in to the income category [categoryId] in [month], in hundredths: the month's total
  /// of it (every row of the month, not only the page of the list loaded so far).
  Future<int> incomeTotal(String month, String categoryId);

  /// Sets the budget of [categoryId] to [cents] (hundredths, not negative) from [month] on
  /// (`PUT /v1/categories/{id}/budget`: `{amount, effectiveFrom}`). The earlier months keep what
  /// they had. Throws a [HomeFailure] when it fails.
  ///
  /// There is no way to clear a budget: the web's sheet refuses zero ("Escribe un monto mayor que
  /// cero") and the API has no delete, so the app has none either.
  Future<void> setBudget(String categoryId, int cents, {required String month});
}

/// [BudgetsRepository] over the generated client.
class ApiBudgetsRepository implements BudgetsRepository {
  ApiBudgetsRepository(this._api);

  final DefaultApi _api;

  static Future<T> _settle<T>(Future<Response<T>> Function() call) async {
    try {
      final data = (await call()).data;
      if (data == null) throw const HomeFailure(500);
      return data;
    } on DioException catch (error) {
      throw HomeFailure.fromDio(error);
    }
  }

  @override
  Future<TransactionsPage> categoryTransactions(
    String month,
    String categoryId, {
    String? cursor,
  }) async {
    final page = await _settle(
      () => _api.listTransactions(
        month: month,
        category: BuiltList<String>([categoryId]),
        cursor: cursor,
        limit: transactionsPageSize,
      ),
    );
    return TransactionsPage(page.items.toList(), page.nextCursor);
  }

  @override
  Future<int> incomeTotal(String month, String categoryId) async {
    final report = await _settle(
      () => _api.getCategoryReport(from: month, to: month, kind: 'income'),
    );
    return report.items.where((i) => i.categoryId == categoryId).map((i) => i.total).firstOrNull ??
        0;
  }

  @override
  Future<void> setBudget(String categoryId, int cents, {required String month}) async {
    await _settle(
      () => _api.setCategoryBudget(
        id: categoryId,
        setBudget: SetBudget(
          (b) => b
            ..amount = cents
            ..effectiveFrom = month,
        ),
      ),
    );
  }
}

/// The budgets repository for the signed-in session (rebuilt when the token changes).
final budgetsRepositoryProvider = Provider<BudgetsRepository>(
  (ref) => ApiBudgetsRepository(ref.watch(apiClientProvider).api.getDefaultApi()),
);
