// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'put_key_wrap.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PutKeyWrapKindEnum _$putKeyWrapKindEnum_passkey = const PutKeyWrapKindEnum._('passkey');
const PutKeyWrapKindEnum _$putKeyWrapKindEnum_recovery = const PutKeyWrapKindEnum._('recovery');
const PutKeyWrapKindEnum _$putKeyWrapKindEnum_device = const PutKeyWrapKindEnum._('device');
const PutKeyWrapKindEnum _$putKeyWrapKindEnum_assistant = const PutKeyWrapKindEnum._('assistant');

PutKeyWrapKindEnum _$putKeyWrapKindEnumValueOf(String name) {
  switch (name) {
    case 'passkey':
      return _$putKeyWrapKindEnum_passkey;
    case 'recovery':
      return _$putKeyWrapKindEnum_recovery;
    case 'device':
      return _$putKeyWrapKindEnum_device;
    case 'assistant':
      return _$putKeyWrapKindEnum_assistant;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PutKeyWrapKindEnum> _$putKeyWrapKindEnumValues = BuiltSet<PutKeyWrapKindEnum>(
  const <PutKeyWrapKindEnum>[
    _$putKeyWrapKindEnum_passkey,
    _$putKeyWrapKindEnum_recovery,
    _$putKeyWrapKindEnum_device,
    _$putKeyWrapKindEnum_assistant,
  ],
);

Serializer<PutKeyWrapKindEnum> _$putKeyWrapKindEnumSerializer = _$PutKeyWrapKindEnumSerializer();

class _$PutKeyWrapKindEnumSerializer implements PrimitiveSerializer<PutKeyWrapKindEnum> {
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
  final Iterable<Type> types = const <Type>[PutKeyWrapKindEnum];
  @override
  final String wireName = 'PutKeyWrapKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    PutKeyWrapKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PutKeyWrapKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) =>
      PutKeyWrapKindEnum.valueOf(_fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$PutKeyWrap extends PutKeyWrap {
  @override
  final PutKeyWrapKindEnum kind;
  @override
  final String? ref;
  @override
  final int keyV;
  @override
  final String wrapped;
  @override
  final String? publicKey;
  @override
  final String? attestation;
  @override
  final String? label;

  factory _$PutKeyWrap([void Function(PutKeyWrapBuilder)? updates]) =>
      (PutKeyWrapBuilder()..update(updates))._build();

  _$PutKeyWrap._({
    required this.kind,
    this.ref,
    required this.keyV,
    required this.wrapped,
    this.publicKey,
    this.attestation,
    this.label,
  }) : super._();
  @override
  PutKeyWrap rebuild(void Function(PutKeyWrapBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PutKeyWrapBuilder toBuilder() => PutKeyWrapBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PutKeyWrap &&
        kind == other.kind &&
        ref == other.ref &&
        keyV == other.keyV &&
        wrapped == other.wrapped &&
        publicKey == other.publicKey &&
        attestation == other.attestation &&
        label == other.label;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, ref.hashCode);
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jc(_$hash, wrapped.hashCode);
    _$hash = $jc(_$hash, publicKey.hashCode);
    _$hash = $jc(_$hash, attestation.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PutKeyWrap')
          ..add('kind', kind)
          ..add('ref', ref)
          ..add('keyV', keyV)
          ..add('wrapped', wrapped)
          ..add('publicKey', publicKey)
          ..add('attestation', attestation)
          ..add('label', label))
        .toString();
  }
}

class PutKeyWrapBuilder implements Builder<PutKeyWrap, PutKeyWrapBuilder> {
  _$PutKeyWrap? _$v;

  PutKeyWrapKindEnum? _kind;
  PutKeyWrapKindEnum? get kind => _$this._kind;
  set kind(PutKeyWrapKindEnum? kind) => _$this._kind = kind;

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

  String? _attestation;
  String? get attestation => _$this._attestation;
  set attestation(String? attestation) => _$this._attestation = attestation;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  PutKeyWrapBuilder() {
    PutKeyWrap._defaults(this);
  }

  PutKeyWrapBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _ref = $v.ref;
      _keyV = $v.keyV;
      _wrapped = $v.wrapped;
      _publicKey = $v.publicKey;
      _attestation = $v.attestation;
      _label = $v.label;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PutKeyWrap other) {
    _$v = other as _$PutKeyWrap;
  }

  @override
  void update(void Function(PutKeyWrapBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PutKeyWrap build() => _build();

  _$PutKeyWrap _build() {
    final _$result =
        _$v ??
        _$PutKeyWrap._(
          kind: BuiltValueNullFieldError.checkNotNull(kind, r'PutKeyWrap', 'kind'),
          ref: ref,
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'PutKeyWrap', 'keyV'),
          wrapped: BuiltValueNullFieldError.checkNotNull(wrapped, r'PutKeyWrap', 'wrapped'),
          publicKey: publicKey,
          attestation: attestation,
          label: label,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
