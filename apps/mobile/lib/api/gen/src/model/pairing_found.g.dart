// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_found.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairingFound extends PairingFound {
  @override
  final String id;
  @override
  final String publicKey;
  @override
  final String expiresAt;

  factory _$PairingFound([void Function(PairingFoundBuilder)? updates]) =>
      (PairingFoundBuilder()..update(updates))._build();

  _$PairingFound._({required this.id, required this.publicKey, required this.expiresAt})
    : super._();
  @override
  PairingFound rebuild(void Function(PairingFoundBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairingFoundBuilder toBuilder() => PairingFoundBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairingFound &&
        id == other.id &&
        publicKey == other.publicKey &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, publicKey.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PairingFound')
          ..add('id', id)
          ..add('publicKey', publicKey)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class PairingFoundBuilder implements Builder<PairingFound, PairingFoundBuilder> {
  _$PairingFound? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _publicKey;
  String? get publicKey => _$this._publicKey;
  set publicKey(String? publicKey) => _$this._publicKey = publicKey;

  String? _expiresAt;
  String? get expiresAt => _$this._expiresAt;
  set expiresAt(String? expiresAt) => _$this._expiresAt = expiresAt;

  PairingFoundBuilder() {
    PairingFound._defaults(this);
  }

  PairingFoundBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _publicKey = $v.publicKey;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairingFound other) {
    _$v = other as _$PairingFound;
  }

  @override
  void update(void Function(PairingFoundBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairingFound build() => _build();

  _$PairingFound _build() {
    final _$result =
        _$v ??
        _$PairingFound._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'PairingFound', 'id'),
          publicKey: BuiltValueNullFieldError.checkNotNull(publicKey, r'PairingFound', 'publicKey'),
          expiresAt: BuiltValueNullFieldError.checkNotNull(expiresAt, r'PairingFound', 'expiresAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
