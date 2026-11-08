// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_page_totals.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TransactionPageTotals extends TransactionPageTotals {
  @override
  final int count;
  @override
  final int expense;
  @override
  final int income;

  factory _$TransactionPageTotals([void Function(TransactionPageTotalsBuilder)? updates]) =>
      (TransactionPageTotalsBuilder()..update(updates))._build();

  _$TransactionPageTotals._({required this.count, required this.expense, required this.income})
    : super._();
  @override
  TransactionPageTotals rebuild(void Function(TransactionPageTotalsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TransactionPageTotalsBuilder toBuilder() => TransactionPageTotalsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TransactionPageTotals &&
        count == other.count &&
        expense == other.expense &&
        income == other.income;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jc(_$hash, expense.hashCode);
    _$hash = $jc(_$hash, income.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TransactionPageTotals')
          ..add('count', count)
          ..add('expense', expense)
          ..add('income', income))
        .toString();
  }
}

class TransactionPageTotalsBuilder
    implements Builder<TransactionPageTotals, TransactionPageTotalsBuilder> {
  _$TransactionPageTotals? _$v;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  int? _expense;
  int? get expense => _$this._expense;
  set expense(int? expense) => _$this._expense = expense;

  int? _income;
  int? get income => _$this._income;
  set income(int? income) => _$this._income = income;

  TransactionPageTotalsBuilder() {
    TransactionPageTotals._defaults(this);
  }

  TransactionPageTotalsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _count = $v.count;
      _expense = $v.expense;
      _income = $v.income;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TransactionPageTotals other) {
    _$v = other as _$TransactionPageTotals;
  }

  @override
  void update(void Function(TransactionPageTotalsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TransactionPageTotals build() => _build();

  _$TransactionPageTotals _build() {
    final _$result =
        _$v ??
        _$TransactionPageTotals._(
          count: BuiltValueNullFieldError.checkNotNull(count, r'TransactionPageTotals', 'count'),
          expense: BuiltValueNullFieldError.checkNotNull(
            expense,
            r'TransactionPageTotals',
            'expense',
          ),
          income: BuiltValueNullFieldError.checkNotNull(income, r'TransactionPageTotals', 'income'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
