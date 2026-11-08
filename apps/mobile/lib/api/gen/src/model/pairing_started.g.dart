// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_started.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairingStarted extends PairingStarted {
  @override
  final String id;
  @override
  final String code;
  @override
  final String expiresAt;

  factory _$PairingStarted([void Function(PairingStartedBuilder)? updates]) =>
      (PairingStartedBuilder()..update(updates))._build();

  _$PairingStarted._({required this.id, required this.code, required this.expiresAt}) : super._();
  @override
  PairingStarted rebuild(void Function(PairingStartedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairingStartedBuilder toBuilder() => PairingStartedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairingStarted &&
        id == other.id &&
        code == other.code &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PairingStarted')
          ..add('id', id)
          ..add('code', code)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class PairingStartedBuilder implements Builder<PairingStarted, PairingStartedBuilder> {
  _$PairingStarted? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _expiresAt;
  String? get expiresAt => _$this._expiresAt;
  set expiresAt(String? expiresAt) => _$this._expiresAt = expiresAt;

  PairingStartedBuilder() {
    PairingStarted._defaults(this);
  }

  PairingStartedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _code = $v.code;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairingStarted other) {
    _$v = other as _$PairingStarted;
  }

  @override
  void update(void Function(PairingStartedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairingStarted build() => _build();

  _$PairingStarted _build() {
    final _$result =
        _$v ??
        _$PairingStarted._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'PairingStarted', 'id'),
          code: BuiltValueNullFieldError.checkNotNull(code, r'PairingStarted', 'code'),
          expiresAt: BuiltValueNullFieldError.checkNotNull(
            expiresAt,
            r'PairingStarted',
            'expiresAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
