// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_pickup.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairingPickup extends PairingPickup {
  @override
  final String sealed_;
  @override
  final int keyV;

  factory _$PairingPickup([void Function(PairingPickupBuilder)? updates]) =>
      (PairingPickupBuilder()..update(updates))._build();

  _$PairingPickup._({required this.sealed_, required this.keyV}) : super._();
  @override
  PairingPickup rebuild(void Function(PairingPickupBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairingPickupBuilder toBuilder() => PairingPickupBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairingPickup && sealed_ == other.sealed_ && keyV == other.keyV;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sealed_.hashCode);
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PairingPickup')
          ..add('sealed_', sealed_)
          ..add('keyV', keyV))
        .toString();
  }
}

class PairingPickupBuilder implements Builder<PairingPickup, PairingPickupBuilder> {
  _$PairingPickup? _$v;

  String? _sealed_;
  String? get sealed_ => _$this._sealed_;
  set sealed_(String? sealed_) => _$this._sealed_ = sealed_;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  PairingPickupBuilder() {
    PairingPickup._defaults(this);
  }

  PairingPickupBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sealed_ = $v.sealed_;
      _keyV = $v.keyV;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairingPickup other) {
    _$v = other as _$PairingPickup;
  }

  @override
  void update(void Function(PairingPickupBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairingPickup build() => _build();

  _$PairingPickup _build() {
    final _$result =
        _$v ??
        _$PairingPickup._(
          sealed_: BuiltValueNullFieldError.checkNotNull(sealed_, r'PairingPickup', 'sealed_'),
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'PairingPickup', 'keyV'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
