// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_source_budgets_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationSourceBudgetsInner extends MigrationSourceBudgetsInner {
  @override
  final String id;
  @override
  final String categoryId;
  @override
  final int amount;
  @override
  final String effectiveFrom;
  @override
  final String createdAt;
  @override
  final String updatedAt;

  factory _$MigrationSourceBudgetsInner([
    void Function(MigrationSourceBudgetsInnerBuilder)? updates,
  ]) => (MigrationSourceBudgetsInnerBuilder()..update(updates))._build();

  _$MigrationSourceBudgetsInner._({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.effectiveFrom,
    required this.createdAt,
    required this.updatedAt,
  }) : super._();
  @override
  MigrationSourceBudgetsInner rebuild(void Function(MigrationSourceBudgetsInnerBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationSourceBudgetsInnerBuilder toBuilder() =>
      MigrationSourceBudgetsInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationSourceBudgetsInner &&
        id == other.id &&
        categoryId == other.categoryId &&
        amount == other.amount &&
        effectiveFrom == other.effectiveFrom &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, amount.hashCode);
    _$hash = $jc(_$hash, effectiveFrom.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationSourceBudgetsInner')
          ..add('id', id)
          ..add('categoryId', categoryId)
          ..add('amount', amount)
          ..add('effectiveFrom', effectiveFrom)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class MigrationSourceBudgetsInnerBuilder
    implements Builder<MigrationSourceBudgetsInner, MigrationSourceBudgetsInnerBuilder> {
  _$MigrationSourceBudgetsInner? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  int? _amount;
  int? get amount => _$this._amount;
  set amount(int? amount) => _$this._amount = amount;

  String? _effectiveFrom;
  String? get effectiveFrom => _$this._effectiveFrom;
  set effectiveFrom(String? effectiveFrom) => _$this._effectiveFrom = effectiveFrom;

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  String? _updatedAt;
  String? get updatedAt => _$this._updatedAt;
  set updatedAt(String? updatedAt) => _$this._updatedAt = updatedAt;

  MigrationSourceBudgetsInnerBuilder() {
    MigrationSourceBudgetsInner._defaults(this);
  }

  MigrationSourceBudgetsInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _categoryId = $v.categoryId;
      _amount = $v.amount;
      _effectiveFrom = $v.effectiveFrom;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationSourceBudgetsInner other) {
    _$v = other as _$MigrationSourceBudgetsInner;
  }

  @override
  void update(void Function(MigrationSourceBudgetsInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationSourceBudgetsInner build() => _build();

  _$MigrationSourceBudgetsInner _build() {
    final _$result =
        _$v ??
        _$MigrationSourceBudgetsInner._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'MigrationSourceBudgetsInner', 'id'),
          categoryId: BuiltValueNullFieldError.checkNotNull(
            categoryId,
            r'MigrationSourceBudgetsInner',
            'categoryId',
          ),
          amount: BuiltValueNullFieldError.checkNotNull(
            amount,
            r'MigrationSourceBudgetsInner',
            'amount',
          ),
          effectiveFrom: BuiltValueNullFieldError.checkNotNull(
            effectiveFrom,
            r'MigrationSourceBudgetsInner',
            'effectiveFrom',
          ),
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'MigrationSourceBudgetsInner',
            'createdAt',
          ),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
            updatedAt,
            r'MigrationSourceBudgetsInner',
            'updatedAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
