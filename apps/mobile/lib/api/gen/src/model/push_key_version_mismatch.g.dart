// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_key_version_mismatch.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PushKeyVersionMismatchErrorEnum _$pushKeyVersionMismatchErrorEnum_keyVersionMismatch =
    const PushKeyVersionMismatchErrorEnum._('keyVersionMismatch');

PushKeyVersionMismatchErrorEnum _$pushKeyVersionMismatchErrorEnumValueOf(String name) {
  switch (name) {
    case 'keyVersionMismatch':
      return _$pushKeyVersionMismatchErrorEnum_keyVersionMismatch;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PushKeyVersionMismatchErrorEnum> _$pushKeyVersionMismatchErrorEnumValues =
    BuiltSet<PushKeyVersionMismatchErrorEnum>(const <PushKeyVersionMismatchErrorEnum>[
      _$pushKeyVersionMismatchErrorEnum_keyVersionMismatch,
    ]);

Serializer<PushKeyVersionMismatchErrorEnum> _$pushKeyVersionMismatchErrorEnumSerializer =
    _$PushKeyVersionMismatchErrorEnumSerializer();

class _$PushKeyVersionMismatchErrorEnumSerializer
    implements PrimitiveSerializer<PushKeyVersionMismatchErrorEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'keyVersionMismatch': 'key_version_mismatch',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'key_version_mismatch': 'keyVersionMismatch',
  };

  @override
  final Iterable<Type> types = const <Type>[PushKeyVersionMismatchErrorEnum];
  @override
  final String wireName = 'PushKeyVersionMismatchErrorEnum';

  @override
  Object serialize(
    Serializers serializers,
    PushKeyVersionMismatchErrorEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PushKeyVersionMismatchErrorEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PushKeyVersionMismatchErrorEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$PushKeyVersionMismatch extends PushKeyVersionMismatch {
  @override
  final String id;
  @override
  final PushKeyVersionMismatchErrorEnum error;
  @override
  final int keyV;

  factory _$PushKeyVersionMismatch([void Function(PushKeyVersionMismatchBuilder)? updates]) =>
      (PushKeyVersionMismatchBuilder()..update(updates))._build();

  _$PushKeyVersionMismatch._({required this.id, required this.error, required this.keyV})
    : super._();
  @override
  PushKeyVersionMismatch rebuild(void Function(PushKeyVersionMismatchBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PushKeyVersionMismatchBuilder toBuilder() => PushKeyVersionMismatchBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushKeyVersionMismatch &&
        id == other.id &&
        error == other.error &&
        keyV == other.keyV;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushKeyVersionMismatch')
          ..add('id', id)
          ..add('error', error)
          ..add('keyV', keyV))
        .toString();
  }
}

class PushKeyVersionMismatchBuilder
    implements Builder<PushKeyVersionMismatch, PushKeyVersionMismatchBuilder> {
  _$PushKeyVersionMismatch? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  PushKeyVersionMismatchErrorEnum? _error;
  PushKeyVersionMismatchErrorEnum? get error => _$this._error;
  set error(PushKeyVersionMismatchErrorEnum? error) => _$this._error = error;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  PushKeyVersionMismatchBuilder() {
    PushKeyVersionMismatch._defaults(this);
  }

  PushKeyVersionMismatchBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _error = $v.error;
      _keyV = $v.keyV;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushKeyVersionMismatch other) {
    _$v = other as _$PushKeyVersionMismatch;
  }

  @override
  void update(void Function(PushKeyVersionMismatchBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushKeyVersionMismatch build() => _build();

  _$PushKeyVersionMismatch _build() {
    final _$result =
        _$v ??
        _$PushKeyVersionMismatch._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'PushKeyVersionMismatch', 'id'),
          error: BuiltValueNullFieldError.checkNotNull(error, r'PushKeyVersionMismatch', 'error'),
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'PushKeyVersionMismatch', 'keyV'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
