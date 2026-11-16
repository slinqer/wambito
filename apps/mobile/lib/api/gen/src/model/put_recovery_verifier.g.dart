// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'put_recovery_verifier.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PutRecoveryVerifier extends PutRecoveryVerifier {
  @override
  final String lookupHash;
  @override
  final String authHash;

  factory _$PutRecoveryVerifier([void Function(PutRecoveryVerifierBuilder)? updates]) =>
      (PutRecoveryVerifierBuilder()..update(updates))._build();

  _$PutRecoveryVerifier._({required this.lookupHash, required this.authHash}) : super._();
  @override
  PutRecoveryVerifier rebuild(void Function(PutRecoveryVerifierBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PutRecoveryVerifierBuilder toBuilder() => PutRecoveryVerifierBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PutRecoveryVerifier &&
        lookupHash == other.lookupHash &&
        authHash == other.authHash;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lookupHash.hashCode);
    _$hash = $jc(_$hash, authHash.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PutRecoveryVerifier')
          ..add('lookupHash', lookupHash)
          ..add('authHash', authHash))
        .toString();
  }
}

class PutRecoveryVerifierBuilder
    implements Builder<PutRecoveryVerifier, PutRecoveryVerifierBuilder> {
  _$PutRecoveryVerifier? _$v;

  String? _lookupHash;
  String? get lookupHash => _$this._lookupHash;
  set lookupHash(String? lookupHash) => _$this._lookupHash = lookupHash;

  String? _authHash;
  String? get authHash => _$this._authHash;
  set authHash(String? authHash) => _$this._authHash = authHash;

  PutRecoveryVerifierBuilder() {
    PutRecoveryVerifier._defaults(this);
  }

  PutRecoveryVerifierBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lookupHash = $v.lookupHash;
      _authHash = $v.authHash;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PutRecoveryVerifier other) {
    _$v = other as _$PutRecoveryVerifier;
  }

  @override
  void update(void Function(PutRecoveryVerifierBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PutRecoveryVerifier build() => _build();

  _$PutRecoveryVerifier _build() {
    final _$result =
        _$v ??
        _$PutRecoveryVerifier._(
          lookupHash: BuiltValueNullFieldError.checkNotNull(
            lookupHash,
            r'PutRecoveryVerifier',
            'lookupHash',
          ),
          authHash: BuiltValueNullFieldError.checkNotNull(
            authHash,
            r'PutRecoveryVerifier',
            'authHash',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
