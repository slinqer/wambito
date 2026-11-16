// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signin_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SigninView extends SigninView {
  @override
  final String? publicKey;
  @override
  final String id;
  @override
  final String commitment;
  @override
  final String label;
  @override
  final String expiresAt;

  factory _$SigninView([void Function(SigninViewBuilder)? updates]) =>
      (SigninViewBuilder()..update(updates))._build();

  _$SigninView._({
    this.publicKey,
    required this.id,
    required this.commitment,
    required this.label,
    required this.expiresAt,
  }) : super._();
  @override
  SigninView rebuild(void Function(SigninViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SigninViewBuilder toBuilder() => SigninViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SigninView &&
        publicKey == other.publicKey &&
        id == other.id &&
        commitment == other.commitment &&
        label == other.label &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, publicKey.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, commitment.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SigninView')
          ..add('publicKey', publicKey)
          ..add('id', id)
          ..add('commitment', commitment)
          ..add('label', label)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class SigninViewBuilder implements Builder<SigninView, SigninViewBuilder>, SigninFoundBuilder {
  _$SigninView? _$v;

  String? _publicKey;
  String? get publicKey => _$this._publicKey;
  set publicKey(covariant String? publicKey) => _$this._publicKey = publicKey;

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

  SigninViewBuilder() {
    SigninView._defaults(this);
  }

  SigninViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _publicKey = $v.publicKey;
      _id = $v.id;
      _commitment = $v.commitment;
      _label = $v.label;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant SigninView other) {
    _$v = other as _$SigninView;
  }

  @override
  void update(void Function(SigninViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SigninView build() => _build();

  _$SigninView _build() {
    final _$result =
        _$v ??
        _$SigninView._(
          publicKey: publicKey,
          id: BuiltValueNullFieldError.checkNotNull(id, r'SigninView', 'id'),
          commitment: BuiltValueNullFieldError.checkNotNull(
            commitment,
            r'SigninView',
            'commitment',
          ),
          label: BuiltValueNullFieldError.checkNotNull(label, r'SigninView', 'label'),
          expiresAt: BuiltValueNullFieldError.checkNotNull(expiresAt, r'SigninView', 'expiresAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
