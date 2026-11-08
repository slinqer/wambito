import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../home/home_repository.dart';

/// What the welcome reads and writes on the server beyond what home reads: the web's
/// apps/web/app/features/onboarding/onboarding-api.ts. Every failure is a [HomeFailure].
abstract interface class OnboardingRepository {
  /// Every category, archived ones included: what "already exists" is decided against
  /// (`GET /v1/categories?includeArchived=true`).
  Future<List<Category>> allCategories();

  /// `POST /v1/categories`. A name already taken is 409 `category_name_taken`.
  Future<Category> createCategory({
    required String name,
    required CategoryKindEnum kind,
    required String icon,
    required String color,
    int? sortOrder,
  });

  /// `PATCH /v1/categories/{id}`: only what is given.
  Future<Category> updateCategory(
    String id, {
    String? name,
    String? icon,
    String? color,
    CategoryKindEnum? kind,
    bool? archived,
  });

  /// A page of up to 200 of the category's transactions, in any month
  /// (`GET /v1/transactions?category=&limit=200`).
  Future<TransactionsPage> categoryTransactions(String categoryId, {String? cursor});

  /// `PUT /v1/categories/{id}/budget`: [cents] from [month] (`YYYY-MM`) on.
  Future<void> setBudget(String categoryId, int cents, {required String month});

  /// `PATCH /v1/me`. A currency change after the first movement is 409 `currency_locked`.
  Future<void> patchMe({String? currency, String? timezone, bool? onboardingCompleted});
}

/// [OnboardingRepository] over the generated client.
class ApiOnboardingRepository implements OnboardingRepository {
  ApiOnboardingRepository(this._api, this._dio);

  final DefaultApi _api;

  /// The client's HTTP client, for `PATCH /v1/me`: the generated client writes the onboarding flag's
  /// `true` as the text "true", which the API refuses.
  final Dio _dio;

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
  Future<List<Category>> allCategories() async =>
      (await _settle(() => _api.listCategories(includeArchived: 'true'))).toList();

  @override
  Future<Category> createCategory({
    required String name,
    required CategoryKindEnum kind,
    required String icon,
    required String color,
    int? sortOrder,
  }) => _settle(
    () => _api.createCategory(
      createCategory: CreateCategory(
        (b) => b
          ..name = name
          ..kind = kind == CategoryKindEnum.income
              ? CreateCategoryKindEnum.income
              : CreateCategoryKindEnum.expense
          ..icon = icon
          ..color = color
          ..sortOrder = sortOrder,
      ),
    ),
  );

  @override
  Future<Category> updateCategory(
    String id, {
    String? name,
    String? icon,
    String? color,
    CategoryKindEnum? kind,
    bool? archived,
  }) => _settle(
    () => _api.updateCategory(
      id: id,
      updateCategory: UpdateCategory(
        (b) => b
          ..name = name
          ..icon = icon
          ..color = color
          ..archived = archived
          ..kind = switch (kind) {
            null => null,
            CategoryKindEnum.income => UpdateCategoryKindEnum.income,
            _ => UpdateCategoryKindEnum.expense,
          },
      ),
    ),
  );

  @override
  Future<TransactionsPage> categoryTransactions(String categoryId, {String? cursor}) async {
    final page = await _settle(
      () => _api.listTransactions(
        category: BuiltList<String>([categoryId]),
        cursor: cursor,
        limit: 200,
      ),
    );
    return TransactionsPage(page.items.toList(), page.nextCursor);
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

  @override
  Future<void> patchMe({String? currency, String? timezone, bool? onboardingCompleted}) async {
    try {
      await _dio.patch<Object?>(
        '/v1/me',
        data: {
          'timezone': ?timezone,
          'currency': ?currency,
          if (onboardingCompleted == true) 'onboardingCompleted': true,
        },
      );
    } on DioException catch (error) {
      throw HomeFailure.fromDio(error);
    }
  }
}

/// The welcome's repository for the signed-in session (rebuilt when the token changes).
final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return ApiOnboardingRepository(client.api.getDefaultApi(), client.dio);
});
