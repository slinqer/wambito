// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signin_pickup.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SigninPickup extends SigninPickup {
  @override
  final String sealed_;
  @override
  final int keyV;
  @override
  final String userId;

  factory _$SigninPickup([void Function(SigninPickupBuilder)? updates]) =>
      (SigninPickupBuilder()..update(updates))._build();

  _$SigninPickup._({required this.sealed_, required this.keyV, required this.userId}) : super._();
  @override
  SigninPickup rebuild(void Function(SigninPickupBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SigninPickupBuilder toBuilder() => SigninPickupBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SigninPickup &&
        sealed_ == other.sealed_ &&
        keyV == other.keyV &&
        userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sealed_.hashCode);
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SigninPickup')
          ..add('sealed_', sealed_)
          ..add('keyV', keyV)
          ..add('userId', userId))
        .toString();
  }
}

class SigninPickupBuilder implements Builder<SigninPickup, SigninPickupBuilder> {
  _$SigninPickup? _$v;

  String? _sealed_;
  String? get sealed_ => _$this._sealed_;
  set sealed_(String? sealed_) => _$this._sealed_ = sealed_;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  SigninPickupBuilder() {
    SigninPickup._defaults(this);
  }

  SigninPickupBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sealed_ = $v.sealed_;
      _keyV = $v.keyV;
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SigninPickup other) {
    _$v = other as _$SigninPickup;
  }

  @override
  void update(void Function(SigninPickupBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SigninPickup build() => _build();

  _$SigninPickup _build() {
    final _$result =
        _$v ??
        _$SigninPickup._(
          sealed_: BuiltValueNullFieldError.checkNotNull(sealed_, r'SigninPickup', 'sealed_'),
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'SigninPickup', 'keyV'),
          userId: BuiltValueNullFieldError.checkNotNull(userId, r'SigninPickup', 'userId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
