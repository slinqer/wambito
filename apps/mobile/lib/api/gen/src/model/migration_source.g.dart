// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_source.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationSource extends MigrationSource {
  @override
  final MigrationSourceProfile profile;
  @override
  final BuiltList<MigrationSourceCategoriesInner> categories;
  @override
  final BuiltList<MigrationSourceBudgetsInner> budgets;
  @override
  final BuiltList<MigrationSourceRecurrencesInner> recurrences;
  @override
  final BuiltList<MigrationSourceTransactionsInner> transactions;
  @override
  final BuiltList<MigrationSourceMerchantsInner> merchants;

  factory _$MigrationSource([void Function(MigrationSourceBuilder)? updates]) =>
      (MigrationSourceBuilder()..update(updates))._build();

  _$MigrationSource._({
    required this.profile,
    required this.categories,
    required this.budgets,
    required this.recurrences,
    required this.transactions,
    required this.merchants,
  }) : super._();
  @override
  MigrationSource rebuild(void Function(MigrationSourceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationSourceBuilder toBuilder() => MigrationSourceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationSource &&
        profile == other.profile &&
        categories == other.categories &&
        budgets == other.budgets &&
        recurrences == other.recurrences &&
        transactions == other.transactions &&
        merchants == other.merchants;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, profile.hashCode);
    _$hash = $jc(_$hash, categories.hashCode);
    _$hash = $jc(_$hash, budgets.hashCode);
    _$hash = $jc(_$hash, recurrences.hashCode);
    _$hash = $jc(_$hash, transactions.hashCode);
    _$hash = $jc(_$hash, merchants.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationSource')
          ..add('profile', profile)
          ..add('categories', categories)
          ..add('budgets', budgets)
          ..add('recurrences', recurrences)
          ..add('transactions', transactions)
          ..add('merchants', merchants))
        .toString();
  }
}

class MigrationSourceBuilder implements Builder<MigrationSource, MigrationSourceBuilder> {
  _$MigrationSource? _$v;

  MigrationSourceProfileBuilder? _profile;
  MigrationSourceProfileBuilder get profile => _$this._profile ??= MigrationSourceProfileBuilder();
  set profile(MigrationSourceProfileBuilder? profile) => _$this._profile = profile;

  ListBuilder<MigrationSourceCategoriesInner>? _categories;
  ListBuilder<MigrationSourceCategoriesInner> get categories =>
      _$this._categories ??= ListBuilder<MigrationSourceCategoriesInner>();
  set categories(ListBuilder<MigrationSourceCategoriesInner>? categories) =>
      _$this._categories = categories;

  ListBuilder<MigrationSourceBudgetsInner>? _budgets;
  ListBuilder<MigrationSourceBudgetsInner> get budgets =>
      _$this._budgets ??= ListBuilder<MigrationSourceBudgetsInner>();
  set budgets(ListBuilder<MigrationSourceBudgetsInner>? budgets) => _$this._budgets = budgets;

  ListBuilder<MigrationSourceRecurrencesInner>? _recurrences;
  ListBuilder<MigrationSourceRecurrencesInner> get recurrences =>
      _$this._recurrences ??= ListBuilder<MigrationSourceRecurrencesInner>();
  set recurrences(ListBuilder<MigrationSourceRecurrencesInner>? recurrences) =>
      _$this._recurrences = recurrences;

  ListBuilder<MigrationSourceTransactionsInner>? _transactions;
  ListBuilder<MigrationSourceTransactionsInner> get transactions =>
      _$this._transactions ??= ListBuilder<MigrationSourceTransactionsInner>();
  set transactions(ListBuilder<MigrationSourceTransactionsInner>? transactions) =>
      _$this._transactions = transactions;

  ListBuilder<MigrationSourceMerchantsInner>? _merchants;
  ListBuilder<MigrationSourceMerchantsInner> get merchants =>
      _$this._merchants ??= ListBuilder<MigrationSourceMerchantsInner>();
  set merchants(ListBuilder<MigrationSourceMerchantsInner>? merchants) =>
      _$this._merchants = merchants;

  MigrationSourceBuilder() {
    MigrationSource._defaults(this);
  }

  MigrationSourceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _profile = $v.profile.toBuilder();
      _categories = $v.categories.toBuilder();
      _budgets = $v.budgets.toBuilder();
      _recurrences = $v.recurrences.toBuilder();
      _transactions = $v.transactions.toBuilder();
      _merchants = $v.merchants.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationSource other) {
    _$v = other as _$MigrationSource;
  }

  @override
  void update(void Function(MigrationSourceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationSource build() => _build();

  _$MigrationSource _build() {
    _$MigrationSource _$result;
    try {
      _$result =
          _$v ??
          _$MigrationSource._(
            profile: profile.build(),
            categories: categories.build(),
            budgets: budgets.build(),
            recurrences: recurrences.build(),
            transactions: transactions.build(),
            merchants: merchants.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'profile';
        profile.build();
        _$failedField = 'categories';
        categories.build();
        _$failedField = 'budgets';
        budgets.build();
        _$failedField = 'recurrences';
        recurrences.build();
        _$failedField = 'transactions';
        transactions.build();
        _$failedField = 'merchants';
        merchants.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'MigrationSource', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
