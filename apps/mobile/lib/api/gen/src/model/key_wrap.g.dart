// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'key_wrap.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const KeyWrapKindEnum _$keyWrapKindEnum_passkey = const KeyWrapKindEnum._('passkey');
const KeyWrapKindEnum _$keyWrapKindEnum_recovery = const KeyWrapKindEnum._('recovery');
const KeyWrapKindEnum _$keyWrapKindEnum_device = const KeyWrapKindEnum._('device');
const KeyWrapKindEnum _$keyWrapKindEnum_assistant = const KeyWrapKindEnum._('assistant');

KeyWrapKindEnum _$keyWrapKindEnumValueOf(String name) {
  switch (name) {
    case 'passkey':
      return _$keyWrapKindEnum_passkey;
    case 'recovery':
      return _$keyWrapKindEnum_recovery;
    case 'device':
      return _$keyWrapKindEnum_device;
    case 'assistant':
      return _$keyWrapKindEnum_assistant;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<KeyWrapKindEnum> _$keyWrapKindEnumValues = BuiltSet<KeyWrapKindEnum>(
  const <KeyWrapKindEnum>[
    _$keyWrapKindEnum_passkey,
    _$keyWrapKindEnum_recovery,
    _$keyWrapKindEnum_device,
    _$keyWrapKindEnum_assistant,
  ],
);

Serializer<KeyWrapKindEnum> _$keyWrapKindEnumSerializer = _$KeyWrapKindEnumSerializer();

class _$KeyWrapKindEnumSerializer implements PrimitiveSerializer<KeyWrapKindEnum> {
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
  final Iterable<Type> types = const <Type>[KeyWrapKindEnum];
  @override
  final String wireName = 'KeyWrapKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    KeyWrapKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  KeyWrapKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => KeyWrapKindEnum.valueOf(_fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$KeyWrap extends KeyWrap {
  @override
  final String id;
  @override
  final KeyWrapKindEnum kind;
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
  @override
  final String createdAt;
  @override
  final String? lastUsedAt;

  factory _$KeyWrap([void Function(KeyWrapBuilder)? updates]) =>
      (KeyWrapBuilder()..update(updates))._build();

  _$KeyWrap._({
    required this.id,
    required this.kind,
    this.ref,
    required this.keyV,
    required this.wrapped,
    this.publicKey,
    this.label,
    required this.createdAt,
    this.lastUsedAt,
  }) : super._();
  @override
  KeyWrap rebuild(void Function(KeyWrapBuilder) updates) => (toBuilder()..update(updates)).build();

  @override
  KeyWrapBuilder toBuilder() => KeyWrapBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is KeyWrap &&
        id == other.id &&
        kind == other.kind &&
        ref == other.ref &&
        keyV == other.keyV &&
        wrapped == other.wrapped &&
        publicKey == other.publicKey &&
        label == other.label &&
        createdAt == other.createdAt &&
        lastUsedAt == other.lastUsedAt;
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
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, lastUsedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'KeyWrap')
          ..add('id', id)
          ..add('kind', kind)
          ..add('ref', ref)
          ..add('keyV', keyV)
          ..add('wrapped', wrapped)
          ..add('publicKey', publicKey)
          ..add('label', label)
          ..add('createdAt', createdAt)
          ..add('lastUsedAt', lastUsedAt))
        .toString();
  }
}

class KeyWrapBuilder implements Builder<KeyWrap, KeyWrapBuilder> {
  _$KeyWrap? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  KeyWrapKindEnum? _kind;
  KeyWrapKindEnum? get kind => _$this._kind;
  set kind(KeyWrapKindEnum? kind) => _$this._kind = kind;

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

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  String? _lastUsedAt;
  String? get lastUsedAt => _$this._lastUsedAt;
  set lastUsedAt(String? lastUsedAt) => _$this._lastUsedAt = lastUsedAt;

  KeyWrapBuilder() {
    KeyWrap._defaults(this);
  }

  KeyWrapBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _kind = $v.kind;
      _ref = $v.ref;
      _keyV = $v.keyV;
      _wrapped = $v.wrapped;
      _publicKey = $v.publicKey;
      _label = $v.label;
      _createdAt = $v.createdAt;
      _lastUsedAt = $v.lastUsedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(KeyWrap other) {
    _$v = other as _$KeyWrap;
  }

  @override
  void update(void Function(KeyWrapBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  KeyWrap build() => _build();

  _$KeyWrap _build() {
    final _$result =
        _$v ??
        _$KeyWrap._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'KeyWrap', 'id'),
          kind: BuiltValueNullFieldError.checkNotNull(kind, r'KeyWrap', 'kind'),
          ref: ref,
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'KeyWrap', 'keyV'),
          wrapped: BuiltValueNullFieldError.checkNotNull(wrapped, r'KeyWrap', 'wrapped'),
          publicKey: publicKey,
          label: label,
          createdAt: BuiltValueNullFieldError.checkNotNull(createdAt, r'KeyWrap', 'createdAt'),
          lastUsedAt: lastUsedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
