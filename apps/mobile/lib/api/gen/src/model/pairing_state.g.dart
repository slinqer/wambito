// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairingState extends PairingState {
  @override
  final String commitment;
  @override
  final String? approverKey;
  @override
  final String? publicKey;
  @override
  final String? sealed_;
  @override
  final int? keyV;
  @override
  final String expiresAt;

  factory _$PairingState([void Function(PairingStateBuilder)? updates]) =>
      (PairingStateBuilder()..update(updates))._build();

  _$PairingState._({
    required this.commitment,
    this.approverKey,
    this.publicKey,
    this.sealed_,
    this.keyV,
    required this.expiresAt,
  }) : super._();
  @override
  PairingState rebuild(void Function(PairingStateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairingStateBuilder toBuilder() => PairingStateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairingState &&
        commitment == other.commitment &&
        approverKey == other.approverKey &&
        publicKey == other.publicKey &&
        sealed_ == other.sealed_ &&
        keyV == other.keyV &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, commitment.hashCode);
    _$hash = $jc(_$hash, approverKey.hashCode);
    _$hash = $jc(_$hash, publicKey.hashCode);
    _$hash = $jc(_$hash, sealed_.hashCode);
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PairingState')
          ..add('commitment', commitment)
          ..add('approverKey', approverKey)
          ..add('publicKey', publicKey)
          ..add('sealed_', sealed_)
          ..add('keyV', keyV)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class PairingStateBuilder implements Builder<PairingState, PairingStateBuilder> {
  _$PairingState? _$v;

  String? _commitment;
  String? get commitment => _$this._commitment;
  set commitment(String? commitment) => _$this._commitment = commitment;

  String? _approverKey;
  String? get approverKey => _$this._approverKey;
  set approverKey(String? approverKey) => _$this._approverKey = approverKey;

  String? _publicKey;
  String? get publicKey => _$this._publicKey;
  set publicKey(String? publicKey) => _$this._publicKey = publicKey;

  String? _sealed_;
  String? get sealed_ => _$this._sealed_;
  set sealed_(String? sealed_) => _$this._sealed_ = sealed_;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  String? _expiresAt;
  String? get expiresAt => _$this._expiresAt;
  set expiresAt(String? expiresAt) => _$this._expiresAt = expiresAt;

  PairingStateBuilder() {
    PairingState._defaults(this);
  }

  PairingStateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _commitment = $v.commitment;
      _approverKey = $v.approverKey;
      _publicKey = $v.publicKey;
      _sealed_ = $v.sealed_;
      _keyV = $v.keyV;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairingState other) {
    _$v = other as _$PairingState;
  }

  @override
  void update(void Function(PairingStateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairingState build() => _build();

  _$PairingState _build() {
    final _$result =
        _$v ??
        _$PairingState._(
          commitment: BuiltValueNullFieldError.checkNotNull(
            commitment,
            r'PairingState',
            'commitment',
          ),
          approverKey: approverKey,
          publicKey: publicKey,
          sealed_: sealed_,
          keyV: keyV,
          expiresAt: BuiltValueNullFieldError.checkNotNull(expiresAt, r'PairingState', 'expiresAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
