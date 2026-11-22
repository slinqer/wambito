// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_counts.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationCounts extends MigrationCounts {
  @override
  final int transaction;
  @override
  final int deletedTransaction;
  @override
  final int category;
  @override
  final int budget;
  @override
  final int recurrence;
  @override
  final int merchant;

  factory _$MigrationCounts([void Function(MigrationCountsBuilder)? updates]) =>
      (MigrationCountsBuilder()..update(updates))._build();

  _$MigrationCounts._({
    required this.transaction,
    required this.deletedTransaction,
    required this.category,
    required this.budget,
    required this.recurrence,
    required this.merchant,
  }) : super._();
  @override
  MigrationCounts rebuild(void Function(MigrationCountsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationCountsBuilder toBuilder() => MigrationCountsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationCounts &&
        transaction == other.transaction &&
        deletedTransaction == other.deletedTransaction &&
        category == other.category &&
        budget == other.budget &&
        recurrence == other.recurrence &&
        merchant == other.merchant;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, transaction.hashCode);
    _$hash = $jc(_$hash, deletedTransaction.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, budget.hashCode);
    _$hash = $jc(_$hash, recurrence.hashCode);
    _$hash = $jc(_$hash, merchant.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationCounts')
          ..add('transaction', transaction)
          ..add('deletedTransaction', deletedTransaction)
          ..add('category', category)
          ..add('budget', budget)
          ..add('recurrence', recurrence)
          ..add('merchant', merchant))
        .toString();
  }
}

class MigrationCountsBuilder implements Builder<MigrationCounts, MigrationCountsBuilder> {
  _$MigrationCounts? _$v;

  int? _transaction;
  int? get transaction => _$this._transaction;
  set transaction(int? transaction) => _$this._transaction = transaction;

  int? _deletedTransaction;
  int? get deletedTransaction => _$this._deletedTransaction;
  set deletedTransaction(int? deletedTransaction) =>
      _$this._deletedTransaction = deletedTransaction;

  int? _category;
  int? get category => _$this._category;
  set category(int? category) => _$this._category = category;

  int? _budget;
  int? get budget => _$this._budget;
  set budget(int? budget) => _$this._budget = budget;

  int? _recurrence;
  int? get recurrence => _$this._recurrence;
  set recurrence(int? recurrence) => _$this._recurrence = recurrence;

  int? _merchant;
  int? get merchant => _$this._merchant;
  set merchant(int? merchant) => _$this._merchant = merchant;

  MigrationCountsBuilder() {
    MigrationCounts._defaults(this);
  }

  MigrationCountsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _transaction = $v.transaction;
      _deletedTransaction = $v.deletedTransaction;
      _category = $v.category;
      _budget = $v.budget;
      _recurrence = $v.recurrence;
      _merchant = $v.merchant;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationCounts other) {
    _$v = other as _$MigrationCounts;
  }

  @override
  void update(void Function(MigrationCountsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationCounts build() => _build();

  _$MigrationCounts _build() {
    final _$result =
        _$v ??
        _$MigrationCounts._(
          transaction: BuiltValueNullFieldError.checkNotNull(
            transaction,
            r'MigrationCounts',
            'transaction',
          ),
          deletedTransaction: BuiltValueNullFieldError.checkNotNull(
            deletedTransaction,
            r'MigrationCounts',
            'deletedTransaction',
          ),
          category: BuiltValueNullFieldError.checkNotNull(category, r'MigrationCounts', 'category'),
          budget: BuiltValueNullFieldError.checkNotNull(budget, r'MigrationCounts', 'budget'),
          recurrence: BuiltValueNullFieldError.checkNotNull(
            recurrence,
            r'MigrationCounts',
            'recurrence',
          ),
          merchant: BuiltValueNullFieldError.checkNotNull(merchant, r'MigrationCounts', 'merchant'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
