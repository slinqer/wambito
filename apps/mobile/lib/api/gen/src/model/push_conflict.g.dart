// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_conflict.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PushConflict extends PushConflict {
  @override
  final String id;
  @override
  final SyncRecord conflict;

  factory _$PushConflict([void Function(PushConflictBuilder)? updates]) =>
      (PushConflictBuilder()..update(updates))._build();

  _$PushConflict._({required this.id, required this.conflict}) : super._();
  @override
  PushConflict rebuild(void Function(PushConflictBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PushConflictBuilder toBuilder() => PushConflictBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushConflict && id == other.id && conflict == other.conflict;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, conflict.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushConflict')
          ..add('id', id)
          ..add('conflict', conflict))
        .toString();
  }
}

class PushConflictBuilder implements Builder<PushConflict, PushConflictBuilder> {
  _$PushConflict? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  SyncRecordBuilder? _conflict;
  SyncRecordBuilder get conflict => _$this._conflict ??= SyncRecordBuilder();
  set conflict(SyncRecordBuilder? conflict) => _$this._conflict = conflict;

  PushConflictBuilder() {
    PushConflict._defaults(this);
  }

  PushConflictBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _conflict = $v.conflict.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushConflict other) {
    _$v = other as _$PushConflict;
  }

  @override
  void update(void Function(PushConflictBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushConflict build() => _build();

  _$PushConflict _build() {
    _$PushConflict _$result;
    try {
      _$result =
          _$v ??
          _$PushConflict._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'PushConflict', 'id'),
            conflict: conflict.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'conflict';
        conflict.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'PushConflict', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
