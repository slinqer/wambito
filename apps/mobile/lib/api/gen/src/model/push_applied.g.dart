// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_applied.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PushApplied extends PushApplied {
  @override
  final String id;
  @override
  final int version;

  factory _$PushApplied([void Function(PushAppliedBuilder)? updates]) =>
      (PushAppliedBuilder()..update(updates))._build();

  _$PushApplied._({required this.id, required this.version}) : super._();
  @override
  PushApplied rebuild(void Function(PushAppliedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PushAppliedBuilder toBuilder() => PushAppliedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushApplied && id == other.id && version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushApplied')
          ..add('id', id)
          ..add('version', version))
        .toString();
  }
}

class PushAppliedBuilder implements Builder<PushApplied, PushAppliedBuilder> {
  _$PushApplied? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  PushAppliedBuilder() {
    PushApplied._defaults(this);
  }

  PushAppliedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushApplied other) {
    _$v = other as _$PushApplied;
  }

  @override
  void update(void Function(PushAppliedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushApplied build() => _build();

  _$PushApplied _build() {
    final _$result =
        _$v ??
        _$PushApplied._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'PushApplied', 'id'),
          version: BuiltValueNullFieldError.checkNotNull(version, r'PushApplied', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
