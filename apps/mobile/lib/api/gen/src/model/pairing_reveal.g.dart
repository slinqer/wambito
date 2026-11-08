// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_reveal.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairingReveal extends PairingReveal {
  @override
  final String publicKey;

  factory _$PairingReveal([void Function(PairingRevealBuilder)? updates]) =>
      (PairingRevealBuilder()..update(updates))._build();

  _$PairingReveal._({required this.publicKey}) : super._();
  @override
  PairingReveal rebuild(void Function(PairingRevealBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairingRevealBuilder toBuilder() => PairingRevealBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairingReveal && publicKey == other.publicKey;
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
    return (newBuiltValueToStringHelper(r'PairingReveal')..add('publicKey', publicKey)).toString();
  }
}

class PairingRevealBuilder implements Builder<PairingReveal, PairingRevealBuilder> {
  _$PairingReveal? _$v;

  String? _publicKey;
  String? get publicKey => _$this._publicKey;
  set publicKey(String? publicKey) => _$this._publicKey = publicKey;

  PairingRevealBuilder() {
    PairingReveal._defaults(this);
  }

  PairingRevealBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _publicKey = $v.publicKey;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairingReveal other) {
    _$v = other as _$PairingReveal;
  }

  @override
  void update(void Function(PairingRevealBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairingReveal build() => _build();

  _$PairingReveal _build() {
    final _$result =
        _$v ??
        _$PairingReveal._(
          publicKey: BuiltValueNullFieldError.checkNotNull(
            publicKey,
            r'PairingReveal',
            'publicKey',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
