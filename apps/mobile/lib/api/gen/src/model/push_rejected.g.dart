// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_rejected.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PushRejectedErrorEnum _$pushRejectedErrorEnum_idTaken = const PushRejectedErrorEnum._(
  'idTaken',
);

PushRejectedErrorEnum _$pushRejectedErrorEnumValueOf(String name) {
  switch (name) {
    case 'idTaken':
      return _$pushRejectedErrorEnum_idTaken;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PushRejectedErrorEnum> _$pushRejectedErrorEnumValues =
    BuiltSet<PushRejectedErrorEnum>(const <PushRejectedErrorEnum>[_$pushRejectedErrorEnum_idTaken]);

Serializer<PushRejectedErrorEnum> _$pushRejectedErrorEnumSerializer =
    _$PushRejectedErrorEnumSerializer();

class _$PushRejectedErrorEnumSerializer implements PrimitiveSerializer<PushRejectedErrorEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{'idTaken': 'id_taken'};
  static const Map<Object, String> _fromWire = const <Object, String>{'id_taken': 'idTaken'};

  @override
  final Iterable<Type> types = const <Type>[PushRejectedErrorEnum];
  @override
  final String wireName = 'PushRejectedErrorEnum';

  @override
  Object serialize(
    Serializers serializers,
    PushRejectedErrorEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PushRejectedErrorEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PushRejectedErrorEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$PushRejected extends PushRejected {
  @override
  final String id;
  @override
  final PushRejectedErrorEnum error;

  factory _$PushRejected([void Function(PushRejectedBuilder)? updates]) =>
      (PushRejectedBuilder()..update(updates))._build();

  _$PushRejected._({required this.id, required this.error}) : super._();
  @override
  PushRejected rebuild(void Function(PushRejectedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PushRejectedBuilder toBuilder() => PushRejectedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushRejected && id == other.id && error == other.error;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushRejected')
          ..add('id', id)
          ..add('error', error))
        .toString();
  }
}

class PushRejectedBuilder implements Builder<PushRejected, PushRejectedBuilder> {
  _$PushRejected? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  PushRejectedErrorEnum? _error;
  PushRejectedErrorEnum? get error => _$this._error;
  set error(PushRejectedErrorEnum? error) => _$this._error = error;

  PushRejectedBuilder() {
    PushRejected._defaults(this);
  }

  PushRejectedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _error = $v.error;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushRejected other) {
    _$v = other as _$PushRejected;
  }

  @override
  void update(void Function(PushRejectedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushRejected build() => _build();

  _$PushRejected _build() {
    final _$result =
        _$v ??
        _$PushRejected._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'PushRejected', 'id'),
          error: BuiltValueNullFieldError.checkNotNull(error, r'PushRejected', 'error'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
