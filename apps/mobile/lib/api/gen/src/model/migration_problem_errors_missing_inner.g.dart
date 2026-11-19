// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_problem_errors_missing_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationProblemErrorsMissingInner extends MigrationProblemErrorsMissingInner {
  @override
  final String type;
  @override
  final String id;

  factory _$MigrationProblemErrorsMissingInner([
    void Function(MigrationProblemErrorsMissingInnerBuilder)? updates,
  ]) => (MigrationProblemErrorsMissingInnerBuilder()..update(updates))._build();

  _$MigrationProblemErrorsMissingInner._({required this.type, required this.id}) : super._();
  @override
  MigrationProblemErrorsMissingInner rebuild(
    void Function(MigrationProblemErrorsMissingInnerBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MigrationProblemErrorsMissingInnerBuilder toBuilder() =>
      MigrationProblemErrorsMissingInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationProblemErrorsMissingInner && type == other.type && id == other.id;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationProblemErrorsMissingInner')
          ..add('type', type)
          ..add('id', id))
        .toString();
  }
}

class MigrationProblemErrorsMissingInnerBuilder
    implements
        Builder<MigrationProblemErrorsMissingInner, MigrationProblemErrorsMissingInnerBuilder> {
  _$MigrationProblemErrorsMissingInner? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  MigrationProblemErrorsMissingInnerBuilder() {
    MigrationProblemErrorsMissingInner._defaults(this);
  }

  MigrationProblemErrorsMissingInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationProblemErrorsMissingInner other) {
    _$v = other as _$MigrationProblemErrorsMissingInner;
  }

  @override
  void update(void Function(MigrationProblemErrorsMissingInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationProblemErrorsMissingInner build() => _build();

  _$MigrationProblemErrorsMissingInner _build() {
    final _$result =
        _$v ??
        _$MigrationProblemErrorsMissingInner._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'MigrationProblemErrorsMissingInner',
            'type',
          ),
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'MigrationProblemErrorsMissingInner',
            'id',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
