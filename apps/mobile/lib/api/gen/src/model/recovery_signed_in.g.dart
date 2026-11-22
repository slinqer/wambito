// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recovery_signed_in.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RecoverySignedIn extends RecoverySignedIn {
  @override
  final String userId;

  factory _$RecoverySignedIn([void Function(RecoverySignedInBuilder)? updates]) =>
      (RecoverySignedInBuilder()..update(updates))._build();

  _$RecoverySignedIn._({required this.userId}) : super._();
  @override
  RecoverySignedIn rebuild(void Function(RecoverySignedInBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RecoverySignedInBuilder toBuilder() => RecoverySignedInBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RecoverySignedIn && userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RecoverySignedIn')..add('userId', userId)).toString();
  }
}

class RecoverySignedInBuilder implements Builder<RecoverySignedIn, RecoverySignedInBuilder> {
  _$RecoverySignedIn? _$v;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  RecoverySignedInBuilder() {
    RecoverySignedIn._defaults(this);
  }

  RecoverySignedInBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RecoverySignedIn other) {
    _$v = other as _$RecoverySignedIn;
  }

  @override
  void update(void Function(RecoverySignedInBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RecoverySignedIn build() => _build();

  _$RecoverySignedIn _build() {
    final _$result =
        _$v ??
        _$RecoverySignedIn._(
          userId: BuiltValueNullFieldError.checkNotNull(userId, r'RecoverySignedIn', 'userId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
