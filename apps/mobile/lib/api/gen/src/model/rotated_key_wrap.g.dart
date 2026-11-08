// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rotated_key_wrap.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const RotatedKeyWrapKindEnum _$rotatedKeyWrapKindEnum_passkey = const RotatedKeyWrapKindEnum._(
  'passkey',
);
const RotatedKeyWrapKindEnum _$rotatedKeyWrapKindEnum_recovery = const RotatedKeyWrapKindEnum._(
  'recovery',
);
const RotatedKeyWrapKindEnum _$rotatedKeyWrapKindEnum_device = const RotatedKeyWrapKindEnum._(
  'device',
);
const RotatedKeyWrapKindEnum _$rotatedKeyWrapKindEnum_assistant = const RotatedKeyWrapKindEnum._(
  'assistant',
);

RotatedKeyWrapKindEnum _$rotatedKeyWrapKindEnumValueOf(String name) {
  switch (name) {
    case 'passkey':
      return _$rotatedKeyWrapKindEnum_passkey;
    case 'recovery':
      return _$rotatedKeyWrapKindEnum_recovery;
    case 'device':
      return _$rotatedKeyWrapKindEnum_device;
    case 'assistant':
      return _$rotatedKeyWrapKindEnum_assistant;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<RotatedKeyWrapKindEnum> _$rotatedKeyWrapKindEnumValues =
    BuiltSet<RotatedKeyWrapKindEnum>(const <RotatedKeyWrapKindEnum>[
      _$rotatedKeyWrapKindEnum_passkey,
      _$rotatedKeyWrapKindEnum_recovery,
      _$rotatedKeyWrapKindEnum_device,
      _$rotatedKeyWrapKindEnum_assistant,
    ]);

Serializer<RotatedKeyWrapKindEnum> _$rotatedKeyWrapKindEnumSerializer =
    _$RotatedKeyWrapKindEnumSerializer();

class _$RotatedKeyWrapKindEnumSerializer implements PrimitiveSerializer<RotatedKeyWrapKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'passkey': 'passkey',
    'recovery': 'recovery',
    'device': 'device',
    'assistant': 'assistant',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'passkey': 'passkey',
    'recovery': 'recovery',
    'device': 'device',
    'assistant': 'assistant',
  };

  @override
  final Iterable<Type> types = const <Type>[RotatedKeyWrapKindEnum];
  @override
  final String wireName = 'RotatedKeyWrapKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    RotatedKeyWrapKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  RotatedKeyWrapKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => RotatedKeyWrapKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$RotatedKeyWrap extends RotatedKeyWrap {
  @override
  final String id;
  @override
  final RotatedKeyWrapKindEnum kind;
  @override
  final String? ref;
  @override
  final int keyV;
  @override
  final String wrapped;
  @override
  final String? publicKey;
  @override
  final String? label;

  factory _$RotatedKeyWrap([void Function(RotatedKeyWrapBuilder)? updates]) =>
      (RotatedKeyWrapBuilder()..update(updates))._build();

  _$RotatedKeyWrap._({
    required this.id,
    required this.kind,
    this.ref,
    required this.keyV,
    required this.wrapped,
    this.publicKey,
    this.label,
  }) : super._();
  @override
  RotatedKeyWrap rebuild(void Function(RotatedKeyWrapBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RotatedKeyWrapBuilder toBuilder() => RotatedKeyWrapBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RotatedKeyWrap &&
        id == other.id &&
        kind == other.kind &&
        ref == other.ref &&
        keyV == other.keyV &&
        wrapped == other.wrapped &&
        publicKey == other.publicKey &&
        label == other.label;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, ref.hashCode);
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jc(_$hash, wrapped.hashCode);
    _$hash = $jc(_$hash, publicKey.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RotatedKeyWrap')
          ..add('id', id)
          ..add('kind', kind)
          ..add('ref', ref)
          ..add('keyV', keyV)
          ..add('wrapped', wrapped)
          ..add('publicKey', publicKey)
          ..add('label', label))
        .toString();
  }
}

class RotatedKeyWrapBuilder implements Builder<RotatedKeyWrap, RotatedKeyWrapBuilder> {
  _$RotatedKeyWrap? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  RotatedKeyWrapKindEnum? _kind;
  RotatedKeyWrapKindEnum? get kind => _$this._kind;
  set kind(RotatedKeyWrapKindEnum? kind) => _$this._kind = kind;

  String? _ref;
  String? get ref => _$this._ref;
  set ref(String? ref) => _$this._ref = ref;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  String? _wrapped;
  String? get wrapped => _$this._wrapped;
  set wrapped(String? wrapped) => _$this._wrapped = wrapped;

  String? _publicKey;
  String? get publicKey => _$this._publicKey;
  set publicKey(String? publicKey) => _$this._publicKey = publicKey;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  RotatedKeyWrapBuilder() {
    RotatedKeyWrap._defaults(this);
  }

  RotatedKeyWrapBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _kind = $v.kind;
      _ref = $v.ref;
      _keyV = $v.keyV;
      _wrapped = $v.wrapped;
      _publicKey = $v.publicKey;
      _label = $v.label;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RotatedKeyWrap other) {
    _$v = other as _$RotatedKeyWrap;
  }

  @override
  void update(void Function(RotatedKeyWrapBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RotatedKeyWrap build() => _build();

  _$RotatedKeyWrap _build() {
    final _$result =
        _$v ??
        _$RotatedKeyWrap._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'RotatedKeyWrap', 'id'),
          kind: BuiltValueNullFieldError.checkNotNull(kind, r'RotatedKeyWrap', 'kind'),
          ref: ref,
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'RotatedKeyWrap', 'keyV'),
          wrapped: BuiltValueNullFieldError.checkNotNull(wrapped, r'RotatedKeyWrap', 'wrapped'),
          publicKey: publicKey,
          label: label,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
