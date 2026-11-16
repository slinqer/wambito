// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signin_found.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract mixin class SigninFoundBuilder {
  void replace(SigninFound other);
  void update(void Function(SigninFoundBuilder) updates);
  String? get id;
  set id(String? id);

  String? get commitment;
  set commitment(String? commitment);

  String? get label;
  set label(String? label);

  String? get expiresAt;
  set expiresAt(String? expiresAt);
}

class _$$SigninFound extends $SigninFound {
  @override
  final String id;
  @override
  final String commitment;
  @override
  final String label;
  @override
  final String expiresAt;

  factory _$$SigninFound([void Function($SigninFoundBuilder)? updates]) =>
      ($SigninFoundBuilder()..update(updates))._build();

  _$$SigninFound._({
    required this.id,
    required this.commitment,
    required this.label,
    required this.expiresAt,
  }) : super._();
  @override
  $SigninFound rebuild(void Function($SigninFoundBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $SigninFoundBuilder toBuilder() => $SigninFoundBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $SigninFound &&
        id == other.id &&
        commitment == other.commitment &&
        label == other.label &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, commitment.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'$SigninFound')
          ..add('id', id)
          ..add('commitment', commitment)
          ..add('label', label)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class $SigninFoundBuilder
    implements Builder<$SigninFound, $SigninFoundBuilder>, SigninFoundBuilder {
  _$$SigninFound? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(covariant String? id) => _$this._id = id;

  String? _commitment;
  String? get commitment => _$this._commitment;
  set commitment(covariant String? commitment) => _$this._commitment = commitment;

  String? _label;
  String? get label => _$this._label;
  set label(covariant String? label) => _$this._label = label;

  String? _expiresAt;
  String? get expiresAt => _$this._expiresAt;
  set expiresAt(covariant String? expiresAt) => _$this._expiresAt = expiresAt;

  $SigninFoundBuilder() {
    $SigninFound._defaults(this);
  }

  $SigninFoundBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _commitment = $v.commitment;
      _label = $v.label;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant $SigninFound other) {
    _$v = other as _$$SigninFound;
  }

  @override
  void update(void Function($SigninFoundBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $SigninFound build() => _build();

  _$$SigninFound _build() {
    final _$result =
        _$v ??
        _$$SigninFound._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'$SigninFound', 'id'),
          commitment: BuiltValueNullFieldError.checkNotNull(
            commitment,
            r'$SigninFound',
            'commitment',
          ),
          label: BuiltValueNullFieldError.checkNotNull(label, r'$SigninFound', 'label'),
          expiresAt: BuiltValueNullFieldError.checkNotNull(expiresAt, r'$SigninFound', 'expiresAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
