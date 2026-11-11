// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'key_wraps.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$KeyWraps extends KeyWraps {
  @override
  final BuiltList<KeyWrap> wraps;
  @override
  final BuiltList<KeyLink> links;

  factory _$KeyWraps([void Function(KeyWrapsBuilder)? updates]) =>
      (KeyWrapsBuilder()..update(updates))._build();

  _$KeyWraps._({required this.wraps, required this.links}) : super._();
  @override
  KeyWraps rebuild(void Function(KeyWrapsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  KeyWrapsBuilder toBuilder() => KeyWrapsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is KeyWraps && wraps == other.wraps && links == other.links;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, wraps.hashCode);
    _$hash = $jc(_$hash, links.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'KeyWraps')
          ..add('wraps', wraps)
          ..add('links', links))
        .toString();
  }
}

class KeyWrapsBuilder implements Builder<KeyWraps, KeyWrapsBuilder> {
  _$KeyWraps? _$v;

  ListBuilder<KeyWrap>? _wraps;
  ListBuilder<KeyWrap> get wraps => _$this._wraps ??= ListBuilder<KeyWrap>();
  set wraps(ListBuilder<KeyWrap>? wraps) => _$this._wraps = wraps;

  ListBuilder<KeyLink>? _links;
  ListBuilder<KeyLink> get links => _$this._links ??= ListBuilder<KeyLink>();
  set links(ListBuilder<KeyLink>? links) => _$this._links = links;

  KeyWrapsBuilder() {
    KeyWraps._defaults(this);
  }

  KeyWrapsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _wraps = $v.wraps.toBuilder();
      _links = $v.links.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(KeyWraps other) {
    _$v = other as _$KeyWraps;
  }

  @override
  void update(void Function(KeyWrapsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  KeyWraps build() => _build();

  _$KeyWraps _build() {
    _$KeyWraps _$result;
    try {
      _$result = _$v ?? _$KeyWraps._(wraps: wraps.build(), links: links.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'wraps';
        wraps.build();
        _$failedField = 'links';
        links.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'KeyWraps', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
