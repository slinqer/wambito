// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seal_pairing.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SealPairing extends SealPairing {
  @override
  final String sealed_;

  factory _$SealPairing([void Function(SealPairingBuilder)? updates]) =>
      (SealPairingBuilder()..update(updates))._build();

  _$SealPairing._({required this.sealed_}) : super._();
  @override
  SealPairing rebuild(void Function(SealPairingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SealPairingBuilder toBuilder() => SealPairingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SealPairing && sealed_ == other.sealed_;
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
    return (newBuiltValueToStringHelper(r'SealPairing')..add('sealed_', sealed_)).toString();
  }
}

class SealPairingBuilder implements Builder<SealPairing, SealPairingBuilder> {
  _$SealPairing? _$v;

  String? _sealed_;
  String? get sealed_ => _$this._sealed_;
  set sealed_(String? sealed_) => _$this._sealed_ = sealed_;

  SealPairingBuilder() {
    SealPairing._defaults(this);
  }

  SealPairingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sealed_ = $v.sealed_;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SealPairing other) {
    _$v = other as _$SealPairing;
  }

  @override
  void update(void Function(SealPairingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SealPairing build() => _build();

  _$SealPairing _build() {
    final _$result =
        _$v ??
        _$SealPairing._(
          sealed_: BuiltValueNullFieldError.checkNotNull(sealed_, r'SealPairing', 'sealed_'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
