// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_approver.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairingApprover extends PairingApprover {
  @override
  final String publicKey;

  factory _$PairingApprover([void Function(PairingApproverBuilder)? updates]) =>
      (PairingApproverBuilder()..update(updates))._build();

  _$PairingApprover._({required this.publicKey}) : super._();
  @override
  PairingApprover rebuild(void Function(PairingApproverBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairingApproverBuilder toBuilder() => PairingApproverBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairingApprover && publicKey == other.publicKey;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, publicKey.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'PairingApprover',
    )..add('publicKey', publicKey)).toString();
  }
}

class PairingApproverBuilder implements Builder<PairingApprover, PairingApproverBuilder> {
  _$PairingApprover? _$v;

  String? _publicKey;
  String? get publicKey => _$this._publicKey;
  set publicKey(String? publicKey) => _$this._publicKey = publicKey;

  PairingApproverBuilder() {
    PairingApprover._defaults(this);
  }

  PairingApproverBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _publicKey = $v.publicKey;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairingApprover other) {
    _$v = other as _$PairingApprover;
  }

  @override
  void update(void Function(PairingApproverBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairingApprover build() => _build();

  _$PairingApprover _build() {
    final _$result =
        _$v ??
        _$PairingApprover._(
          publicKey: BuiltValueNullFieldError.checkNotNull(
            publicKey,
            r'PairingApprover',
            'publicKey',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
