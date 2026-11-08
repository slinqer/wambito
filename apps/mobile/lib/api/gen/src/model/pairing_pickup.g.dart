// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_pickup.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairingPickup extends PairingPickup {
  @override
  final String? sealed_;

  factory _$PairingPickup([void Function(PairingPickupBuilder)? updates]) =>
      (PairingPickupBuilder()..update(updates))._build();

  _$PairingPickup._({this.sealed_}) : super._();
  @override
  PairingPickup rebuild(void Function(PairingPickupBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairingPickupBuilder toBuilder() => PairingPickupBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairingPickup && sealed_ == other.sealed_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sealed_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PairingPickup')..add('sealed_', sealed_)).toString();
  }
}

class PairingPickupBuilder implements Builder<PairingPickup, PairingPickupBuilder> {
  _$PairingPickup? _$v;

  String? _sealed_;
  String? get sealed_ => _$this._sealed_;
  set sealed_(String? sealed_) => _$this._sealed_ = sealed_;

  PairingPickupBuilder() {
    PairingPickup._defaults(this);
  }

  PairingPickupBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sealed_ = $v.sealed_;
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
    final _$result = _$v ?? _$PairingPickup._(sealed_: sealed_);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
