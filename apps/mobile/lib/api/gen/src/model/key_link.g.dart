// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'key_link.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$KeyLink extends KeyLink {
  @override
  final int keyV;
  @override
  final String link;

  factory _$KeyLink([void Function(KeyLinkBuilder)? updates]) =>
      (KeyLinkBuilder()..update(updates))._build();

  _$KeyLink._({required this.keyV, required this.link}) : super._();
  @override
  KeyLink rebuild(void Function(KeyLinkBuilder) updates) => (toBuilder()..update(updates)).build();

  @override
  KeyLinkBuilder toBuilder() => KeyLinkBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is KeyLink && keyV == other.keyV && link == other.link;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jc(_$hash, link.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'KeyLink')
          ..add('keyV', keyV)
          ..add('link', link))
        .toString();
  }
}

class KeyLinkBuilder implements Builder<KeyLink, KeyLinkBuilder> {
  _$KeyLink? _$v;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  String? _link;
  String? get link => _$this._link;
  set link(String? link) => _$this._link = link;

  KeyLinkBuilder() {
    KeyLink._defaults(this);
  }

  KeyLinkBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _keyV = $v.keyV;
      _link = $v.link;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(KeyLink other) {
    _$v = other as _$KeyLink;
  }

  @override
  void update(void Function(KeyLinkBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  KeyLink build() => _build();

  _$KeyLink _build() {
    final _$result =
        _$v ??
        _$KeyLink._(
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'KeyLink', 'keyV'),
          link: BuiltValueNullFieldError.checkNotNull(link, r'KeyLink', 'link'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
