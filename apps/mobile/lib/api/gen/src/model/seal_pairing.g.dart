// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seal_pairing.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SealPairing extends SealPairing {
  @override
  final String sealed_;
  @override
  final int keyV;

  factory _$SealPairing([void Function(SealPairingBuilder)? updates]) =>
      (SealPairingBuilder()..update(updates))._build();

  _$SealPairing._({required this.sealed_, required this.keyV}) : super._();
  @override
  SealPairing rebuild(void Function(SealPairingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SealPairingBuilder toBuilder() => SealPairingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SealPairing && sealed_ == other.sealed_ && keyV == other.keyV;
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
    return (newBuiltValueToStringHelper(r'SealPairing')
          ..add('sealed_', sealed_)
          ..add('keyV', keyV))
        .toString();
  }
}

class SealPairingBuilder implements Builder<SealPairing, SealPairingBuilder> {
  _$SealPairing? _$v;

  String? _sealed_;
  String? get sealed_ => _$this._sealed_;
  set sealed_(String? sealed_) => _$this._sealed_ = sealed_;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  SealPairingBuilder() {
    SealPairing._defaults(this);
  }

  SealPairingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sealed_ = $v.sealed_;
      _keyV = $v.keyV;
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
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'SealPairing', 'keyV'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
