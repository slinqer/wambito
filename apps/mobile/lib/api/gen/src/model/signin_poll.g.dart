// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signin_poll.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SigninPoll extends SigninPoll {
  @override
  final String? approverKey;
  @override
  final bool ready;
  @override
  final String expiresAt;

  factory _$SigninPoll([void Function(SigninPollBuilder)? updates]) =>
      (SigninPollBuilder()..update(updates))._build();

  _$SigninPoll._({this.approverKey, required this.ready, required this.expiresAt}) : super._();
  @override
  SigninPoll rebuild(void Function(SigninPollBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SigninPollBuilder toBuilder() => SigninPollBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SigninPoll &&
        approverKey == other.approverKey &&
        ready == other.ready &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, approverKey.hashCode);
    _$hash = $jc(_$hash, ready.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SigninPoll')
          ..add('approverKey', approverKey)
          ..add('ready', ready)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class SigninPollBuilder implements Builder<SigninPoll, SigninPollBuilder> {
  _$SigninPoll? _$v;

  String? _approverKey;
  String? get approverKey => _$this._approverKey;
  set approverKey(String? approverKey) => _$this._approverKey = approverKey;

  bool? _ready;
  bool? get ready => _$this._ready;
  set ready(bool? ready) => _$this._ready = ready;

  String? _expiresAt;
  String? get expiresAt => _$this._expiresAt;
  set expiresAt(String? expiresAt) => _$this._expiresAt = expiresAt;

  SigninPollBuilder() {
    SigninPoll._defaults(this);
  }

  SigninPollBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _approverKey = $v.approverKey;
      _ready = $v.ready;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SigninPoll other) {
    _$v = other as _$SigninPoll;
  }

  @override
  void update(void Function(SigninPollBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SigninPoll build() => _build();

  _$SigninPoll _build() {
    final _$result =
        _$v ??
        _$SigninPoll._(
          approverKey: approverKey,
          ready: BuiltValueNullFieldError.checkNotNull(ready, r'SigninPoll', 'ready'),
          expiresAt: BuiltValueNullFieldError.checkNotNull(expiresAt, r'SigninPoll', 'expiresAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
