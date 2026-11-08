// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PushResultErrorEnum _$pushResultErrorEnum_idTaken = const PushResultErrorEnum._('idTaken');
const PushResultErrorEnum _$pushResultErrorEnum_notFound = const PushResultErrorEnum._('notFound');

PushResultErrorEnum _$pushResultErrorEnumValueOf(String name) {
  switch (name) {
    case 'idTaken':
      return _$pushResultErrorEnum_idTaken;
    case 'notFound':
      return _$pushResultErrorEnum_notFound;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PushResultErrorEnum> _$pushResultErrorEnumValues = BuiltSet<PushResultErrorEnum>(
  const <PushResultErrorEnum>[_$pushResultErrorEnum_idTaken, _$pushResultErrorEnum_notFound],
);

Serializer<PushResultErrorEnum> _$pushResultErrorEnumSerializer = _$PushResultErrorEnumSerializer();

class _$PushResultErrorEnumSerializer implements PrimitiveSerializer<PushResultErrorEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'idTaken': 'id_taken',
    'notFound': 'not_found',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'id_taken': 'idTaken',
    'not_found': 'notFound',
  };

  @override
  final Iterable<Type> types = const <Type>[PushResultErrorEnum];
  @override
  final String wireName = 'PushResultErrorEnum';

  @override
  Object serialize(
    Serializers serializers,
    PushResultErrorEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PushResultErrorEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PushResultErrorEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$PushResult extends PushResult {
  @override
  final AnyOf anyOf;

  factory _$PushResult([void Function(PushResultBuilder)? updates]) =>
      (PushResultBuilder()..update(updates))._build();

  _$PushResult._({required this.anyOf}) : super._();
  @override
  PushResult rebuild(void Function(PushResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PushResultBuilder toBuilder() => PushResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushResult && anyOf == other.anyOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, anyOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushResult')..add('anyOf', anyOf)).toString();
  }
}

class PushResultBuilder implements Builder<PushResult, PushResultBuilder> {
  _$PushResult? _$v;

  AnyOf? _anyOf;
  AnyOf? get anyOf => _$this._anyOf;
  set anyOf(AnyOf? anyOf) => _$this._anyOf = anyOf;

  PushResultBuilder() {
    PushResult._defaults(this);
  }

  PushResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _anyOf = $v.anyOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushResult other) {
    _$v = other as _$PushResult;
  }

  @override
  void update(void Function(PushResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushResult build() => _build();

  _$PushResult _build() {
    final _$result =
        _$v ??
        _$PushResult._(anyOf: BuiltValueNullFieldError.checkNotNull(anyOf, r'PushResult', 'anyOf'));
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
