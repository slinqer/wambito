import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../home/home_repository.dart';
import 'category_model.dart';

/// What managing categories reads and changes on the server, as the web's queries do
/// (apps/web/app/api/queries.ts `useCreateCategory`, `useUpdateCategory`, and onboarding-api.ts
/// `countCategoryTransactions`). The list of categories is home's ([HomeRepository.categories]).
abstract interface class CategoriesRepository {
  /// Creates a category (`POST /v1/categories`). Throws a [HomeFailure] with the API's `code`
  /// (`category_name_taken`, `validation_failed`).
  Future<Category> create(NewCategory values);

  /// Changes a category (`PATCH /v1/categories/{id}`): only what is given. [archived] archives it
  /// (the server also ends its recurring payments, from today, and drops their unpaid rows from
  /// today on) or brings it back. Throws a [HomeFailure] (`category_name_taken`,
  /// `category_has_transactions` for a kind change).
  Future<Category> update(
    String id, {
    String? name,
    String? icon,
    String? color,
    CategoryKindEnum? kind,
    bool? archived,
  });

  /// Whether the category has any transaction, in any month: its kind is then fixed (the API
  /// refuses the change with 409 `category_has_transactions`; this only says so up front).
  Future<bool> hasTransactions(String categoryId);

  /// The account's recurring payments, to say how many archiving a category stops.
  Future<List<Recurrence>> recurrences();
}

/// [CategoriesRepository] over the generated client.
class ApiCategoriesRepository implements CategoriesRepository {
  ApiCategoriesRepository(this._api);

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
  Future<Category> create(NewCategory values) => _settle(
    () => _api.createCategory(
      createCategory: CreateCategory(
        (b) => b
          ..name = values.name
          ..kind = switch (values.kind) {
            CategoryKindEnum.income => CreateCategoryKindEnum.income,
            _ => CreateCategoryKindEnum.expense,
          }
          ..icon = values.glyph
          ..color = values.tint,
      ),
    ),
  );

  @override
  Future<Category> update(
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
  Future<bool> hasTransactions(String categoryId) async {
    // The web's one page (200 rows) of the category's transactions: enough to know.
    final page = await _settle(
      () => _api.listTransactions(category: BuiltList<String>([categoryId]), limit: 200),
    );
    return page.items.isNotEmpty;
  }

  @override
  Future<List<Recurrence>> recurrences() async =>
      (await _settle(() => _api.listRecurrences())).toList();
}

/// The categories repository for the signed-in session (rebuilt when the token changes).
final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => ApiCategoriesRepository(ref.watch(apiClientProvider).api.getDefaultApi()),
);
