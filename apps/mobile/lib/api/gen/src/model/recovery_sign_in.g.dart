// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recovery_sign_in.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RecoverySignIn extends RecoverySignIn {
  @override
  final String lookup;
  @override
  final String auth;

  factory _$RecoverySignIn([void Function(RecoverySignInBuilder)? updates]) =>
      (RecoverySignInBuilder()..update(updates))._build();

  _$RecoverySignIn._({required this.lookup, required this.auth}) : super._();
  @override
  RecoverySignIn rebuild(void Function(RecoverySignInBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RecoverySignInBuilder toBuilder() => RecoverySignInBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RecoverySignIn && lookup == other.lookup && auth == other.auth;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lookup.hashCode);
    _$hash = $jc(_$hash, auth.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RecoverySignIn')
          ..add('lookup', lookup)
          ..add('auth', auth))
        .toString();
  }
}

class RecoverySignInBuilder implements Builder<RecoverySignIn, RecoverySignInBuilder> {
  _$RecoverySignIn? _$v;

  String? _lookup;
  String? get lookup => _$this._lookup;
  set lookup(String? lookup) => _$this._lookup = lookup;

  String? _auth;
  String? get auth => _$this._auth;
  set auth(String? auth) => _$this._auth = auth;

  RecoverySignInBuilder() {
    RecoverySignIn._defaults(this);
  }

  RecoverySignInBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lookup = $v.lookup;
      _auth = $v.auth;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RecoverySignIn other) {
    _$v = other as _$RecoverySignIn;
  }

  @override
  void update(void Function(RecoverySignInBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RecoverySignIn build() => _build();

  _$RecoverySignIn _build() {
    final _$result =
        _$v ??
        _$RecoverySignIn._(
          lookup: BuiltValueNullFieldError.checkNotNull(lookup, r'RecoverySignIn', 'lookup'),
          auth: BuiltValueNullFieldError.checkNotNull(auth, r'RecoverySignIn', 'auth'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
