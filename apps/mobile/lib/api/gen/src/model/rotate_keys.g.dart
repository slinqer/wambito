// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rotate_keys.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RotateKeys extends RotateKeys {
  @override
  final int keyV;
  @override
  final BuiltList<RotatedKeyWrap> wraps;
  @override
  final String? link;

  factory _$RotateKeys([void Function(RotateKeysBuilder)? updates]) =>
      (RotateKeysBuilder()..update(updates))._build();

  _$RotateKeys._({required this.keyV, required this.wraps, this.link}) : super._();
  @override
  RotateKeys rebuild(void Function(RotateKeysBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RotateKeysBuilder toBuilder() => RotateKeysBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RotateKeys && keyV == other.keyV && wraps == other.wraps && link == other.link;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jc(_$hash, wraps.hashCode);
    _$hash = $jc(_$hash, link.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RotateKeys')
          ..add('keyV', keyV)
          ..add('wraps', wraps)
          ..add('link', link))
        .toString();
  }
}

class RotateKeysBuilder implements Builder<RotateKeys, RotateKeysBuilder> {
  _$RotateKeys? _$v;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  ListBuilder<RotatedKeyWrap>? _wraps;
  ListBuilder<RotatedKeyWrap> get wraps => _$this._wraps ??= ListBuilder<RotatedKeyWrap>();
  set wraps(ListBuilder<RotatedKeyWrap>? wraps) => _$this._wraps = wraps;

  String? _link;
  String? get link => _$this._link;
  set link(String? link) => _$this._link = link;

  RotateKeysBuilder() {
    RotateKeys._defaults(this);
  }

  RotateKeysBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _keyV = $v.keyV;
      _wraps = $v.wraps.toBuilder();
      _link = $v.link;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RotateKeys other) {
    _$v = other as _$RotateKeys;
  }

  @override
  void update(void Function(RotateKeysBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RotateKeys build() => _build();

  _$RotateKeys _build() {
    _$RotateKeys _$result;
    try {
      _$result =
          _$v ??
          _$RotateKeys._(
            keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'RotateKeys', 'keyV'),
            wraps: wraps.build(),
            link: link,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'wraps';
        wraps.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'RotateKeys', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
