// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_signin.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StartSignin extends StartSignin {
  @override
  final String commitment;
  @override
  final bool remember;
  @override
  final String label;

  factory _$StartSignin([void Function(StartSigninBuilder)? updates]) =>
      (StartSigninBuilder()..update(updates))._build();

  _$StartSignin._({required this.commitment, required this.remember, required this.label})
    : super._();
  @override
  StartSignin rebuild(void Function(StartSigninBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StartSigninBuilder toBuilder() => StartSigninBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StartSignin &&
        commitment == other.commitment &&
        remember == other.remember &&
        label == other.label;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, commitment.hashCode);
    _$hash = $jc(_$hash, remember.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StartSignin')
          ..add('commitment', commitment)
          ..add('remember', remember)
          ..add('label', label))
        .toString();
  }
}

class StartSigninBuilder implements Builder<StartSignin, StartSigninBuilder> {
  _$StartSignin? _$v;

  String? _commitment;
  String? get commitment => _$this._commitment;
  set commitment(String? commitment) => _$this._commitment = commitment;

  bool? _remember;
  bool? get remember => _$this._remember;
  set remember(bool? remember) => _$this._remember = remember;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  StartSigninBuilder() {
    StartSignin._defaults(this);
  }

  StartSigninBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _commitment = $v.commitment;
      _remember = $v.remember;
      _label = $v.label;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StartSignin other) {
    _$v = other as _$StartSignin;
  }

  @override
  void update(void Function(StartSigninBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StartSignin build() => _build();

  _$StartSignin _build() {
    final _$result =
        _$v ??
        _$StartSignin._(
          commitment: BuiltValueNullFieldError.checkNotNull(
            commitment,
            r'StartSignin',
            'commitment',
          ),
          remember: BuiltValueNullFieldError.checkNotNull(remember, r'StartSignin', 'remember'),
          label: BuiltValueNullFieldError.checkNotNull(label, r'StartSignin', 'label'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
