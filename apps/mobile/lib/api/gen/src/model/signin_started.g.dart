// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signin_started.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SigninStarted extends SigninStarted {
  @override
  final String id;
  @override
  final String code;
  @override
  final String pollSecret;
  @override
  final String expiresAt;

  factory _$SigninStarted([void Function(SigninStartedBuilder)? updates]) =>
      (SigninStartedBuilder()..update(updates))._build();

  _$SigninStarted._({
    required this.id,
    required this.code,
    required this.pollSecret,
    required this.expiresAt,
  }) : super._();
  @override
  SigninStarted rebuild(void Function(SigninStartedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SigninStartedBuilder toBuilder() => SigninStartedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SigninStarted &&
        id == other.id &&
        code == other.code &&
        pollSecret == other.pollSecret &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, pollSecret.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SigninStarted')
          ..add('id', id)
          ..add('code', code)
          ..add('pollSecret', pollSecret)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class SigninStartedBuilder implements Builder<SigninStarted, SigninStartedBuilder> {
  _$SigninStarted? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _pollSecret;
  String? get pollSecret => _$this._pollSecret;
  set pollSecret(String? pollSecret) => _$this._pollSecret = pollSecret;

  String? _expiresAt;
  String? get expiresAt => _$this._expiresAt;
  set expiresAt(String? expiresAt) => _$this._expiresAt = expiresAt;

  SigninStartedBuilder() {
    SigninStarted._defaults(this);
  }

  SigninStartedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _code = $v.code;
      _pollSecret = $v.pollSecret;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SigninStarted other) {
    _$v = other as _$SigninStarted;
  }

  @override
  void update(void Function(SigninStartedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SigninStarted build() => _build();

  _$SigninStarted _build() {
    final _$result =
        _$v ??
        _$SigninStarted._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'SigninStarted', 'id'),
          code: BuiltValueNullFieldError.checkNotNull(code, r'SigninStarted', 'code'),
          pollSecret: BuiltValueNullFieldError.checkNotNull(
            pollSecret,
            r'SigninStarted',
            'pollSecret',
          ),
          expiresAt: BuiltValueNullFieldError.checkNotNull(
            expiresAt,
            r'SigninStarted',
            'expiresAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
