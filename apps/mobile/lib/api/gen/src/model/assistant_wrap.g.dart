// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assistant_wrap.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AssistantWrap extends AssistantWrap {
  @override
  final KeyWrap wrap;
  @override
  final BuiltList<KeyLink> links;

  factory _$AssistantWrap([void Function(AssistantWrapBuilder)? updates]) =>
      (AssistantWrapBuilder()..update(updates))._build();

  _$AssistantWrap._({required this.wrap, required this.links}) : super._();
  @override
  AssistantWrap rebuild(void Function(AssistantWrapBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AssistantWrapBuilder toBuilder() => AssistantWrapBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AssistantWrap && wrap == other.wrap && links == other.links;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, wrap.hashCode);
    _$hash = $jc(_$hash, links.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AssistantWrap')
          ..add('wrap', wrap)
          ..add('links', links))
        .toString();
  }
}

class AssistantWrapBuilder implements Builder<AssistantWrap, AssistantWrapBuilder> {
  _$AssistantWrap? _$v;

  KeyWrapBuilder? _wrap;
  KeyWrapBuilder get wrap => _$this._wrap ??= KeyWrapBuilder();
  set wrap(KeyWrapBuilder? wrap) => _$this._wrap = wrap;

  ListBuilder<KeyLink>? _links;
  ListBuilder<KeyLink> get links => _$this._links ??= ListBuilder<KeyLink>();
  set links(ListBuilder<KeyLink>? links) => _$this._links = links;

  AssistantWrapBuilder() {
    AssistantWrap._defaults(this);
  }

  AssistantWrapBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _wrap = $v.wrap.toBuilder();
      _links = $v.links.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AssistantWrap other) {
    _$v = other as _$AssistantWrap;
  }

  @override
  void update(void Function(AssistantWrapBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AssistantWrap build() => _build();

  _$AssistantWrap _build() {
    _$AssistantWrap _$result;
    try {
      _$result = _$v ?? _$AssistantWrap._(wrap: wrap.build(), links: links.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'wrap';
        wrap.build();
        _$failedField = 'links';
        links.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'AssistantWrap', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
