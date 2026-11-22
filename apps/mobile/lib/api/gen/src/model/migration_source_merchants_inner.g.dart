// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_source_merchants_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationSourceMerchantsInner extends MigrationSourceMerchantsInner {
  @override
  final String id;
  @override
  final String merchantKey;
  @override
  final String categoryId;
  @override
  final String createdAt;
  @override
  final String updatedAt;

  factory _$MigrationSourceMerchantsInner([
    void Function(MigrationSourceMerchantsInnerBuilder)? updates,
  ]) => (MigrationSourceMerchantsInnerBuilder()..update(updates))._build();

  _$MigrationSourceMerchantsInner._({
    required this.id,
    required this.merchantKey,
    required this.categoryId,
    required this.createdAt,
    required this.updatedAt,
  }) : super._();
  @override
  MigrationSourceMerchantsInner rebuild(
    void Function(MigrationSourceMerchantsInnerBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MigrationSourceMerchantsInnerBuilder toBuilder() =>
      MigrationSourceMerchantsInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationSourceMerchantsInner &&
        id == other.id &&
        merchantKey == other.merchantKey &&
        categoryId == other.categoryId &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, merchantKey.hashCode);
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationSourceMerchantsInner')
          ..add('id', id)
          ..add('merchantKey', merchantKey)
          ..add('categoryId', categoryId)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class MigrationSourceMerchantsInnerBuilder
    implements Builder<MigrationSourceMerchantsInner, MigrationSourceMerchantsInnerBuilder> {
  _$MigrationSourceMerchantsInner? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _merchantKey;
  String? get merchantKey => _$this._merchantKey;
  set merchantKey(String? merchantKey) => _$this._merchantKey = merchantKey;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  String? _updatedAt;
  String? get updatedAt => _$this._updatedAt;
  set updatedAt(String? updatedAt) => _$this._updatedAt = updatedAt;

  MigrationSourceMerchantsInnerBuilder() {
    MigrationSourceMerchantsInner._defaults(this);
  }

  MigrationSourceMerchantsInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _merchantKey = $v.merchantKey;
      _categoryId = $v.categoryId;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationSourceMerchantsInner other) {
    _$v = other as _$MigrationSourceMerchantsInner;
  }

  @override
  void update(void Function(MigrationSourceMerchantsInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationSourceMerchantsInner build() => _build();

  _$MigrationSourceMerchantsInner _build() {
    final _$result =
        _$v ??
        _$MigrationSourceMerchantsInner._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'MigrationSourceMerchantsInner', 'id'),
          merchantKey: BuiltValueNullFieldError.checkNotNull(
            merchantKey,
            r'MigrationSourceMerchantsInner',
            'merchantKey',
          ),
          categoryId: BuiltValueNullFieldError.checkNotNull(
            categoryId,
            r'MigrationSourceMerchantsInner',
            'categoryId',
          ),
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'MigrationSourceMerchantsInner',
            'createdAt',
          ),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
            updatedAt,
            r'MigrationSourceMerchantsInner',
            'updatedAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
