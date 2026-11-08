// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_pairing.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StartPairing extends StartPairing {
  @override
  final String commitment;

  factory _$StartPairing([void Function(StartPairingBuilder)? updates]) =>
      (StartPairingBuilder()..update(updates))._build();

  _$StartPairing._({required this.commitment}) : super._();
  @override
  StartPairing rebuild(void Function(StartPairingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StartPairingBuilder toBuilder() => StartPairingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StartPairing && commitment == other.commitment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, commitment.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StartPairing')..add('commitment', commitment)).toString();
  }
}

class StartPairingBuilder implements Builder<StartPairing, StartPairingBuilder> {
  _$StartPairing? _$v;

  String? _commitment;
  String? get commitment => _$this._commitment;
  set commitment(String? commitment) => _$this._commitment = commitment;

  StartPairingBuilder() {
    StartPairing._defaults(this);
  }

  StartPairingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _commitment = $v.commitment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StartPairing other) {
    _$v = other as _$StartPairing;
  }

  @override
  void update(void Function(StartPairingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StartPairing build() => _build();

  _$StartPairing _build() {
    final _$result =
        _$v ??
        _$StartPairing._(
          commitment: BuiltValueNullFieldError.checkNotNull(
            commitment,
            r'StartPairing',
            'commitment',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
