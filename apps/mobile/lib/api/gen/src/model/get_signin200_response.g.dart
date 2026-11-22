// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'get_signin200_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GetSignin200Response extends GetSignin200Response {
  @override
  final AnyOf anyOf;

  factory _$GetSignin200Response([void Function(GetSignin200ResponseBuilder)? updates]) =>
      (GetSignin200ResponseBuilder()..update(updates))._build();

  _$GetSignin200Response._({required this.anyOf}) : super._();
  @override
  GetSignin200Response rebuild(void Function(GetSignin200ResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GetSignin200ResponseBuilder toBuilder() => GetSignin200ResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GetSignin200Response && anyOf == other.anyOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, anyOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GetSignin200Response')..add('anyOf', anyOf)).toString();
  }
}

class GetSignin200ResponseBuilder
    implements Builder<GetSignin200Response, GetSignin200ResponseBuilder> {
  _$GetSignin200Response? _$v;

  AnyOf? _anyOf;
  AnyOf? get anyOf => _$this._anyOf;
  set anyOf(AnyOf? anyOf) => _$this._anyOf = anyOf;

  GetSignin200ResponseBuilder() {
    GetSignin200Response._defaults(this);
  }

  GetSignin200ResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _anyOf = $v.anyOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GetSignin200Response other) {
    _$v = other as _$GetSignin200Response;
  }

  @override
  void update(void Function(GetSignin200ResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GetSignin200Response build() => _build();

  _$GetSignin200Response _build() {
    final _$result =
        _$v ??
        _$GetSignin200Response._(
          anyOf: BuiltValueNullFieldError.checkNotNull(anyOf, r'GetSignin200Response', 'anyOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
