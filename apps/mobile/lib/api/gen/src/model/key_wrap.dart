//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'key_wrap.g.dart';

/// KeyWrap
///
/// Properties:
/// * [id]
/// * [kind]
/// * [ref]
/// * [keyV]
/// * [wrapped] - base64url without padding
/// * [publicKey] - base64url without padding
/// * [attestation] - `device` only; base64url without padding
/// * [label]
/// * [createdAt]
/// * [lastUsedAt]
@BuiltValue()
abstract class KeyWrap implements Built<KeyWrap, KeyWrapBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'kind')
  KeyWrapKindEnum get kind;
  // enum kindEnum {  passkey,  recovery,  device,  assistant,  };

  @BuiltValueField(wireName: r'ref')
  String? get ref;

  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  /// base64url without padding
  @BuiltValueField(wireName: r'wrapped')
  String get wrapped;

  /// base64url without padding
  @BuiltValueField(wireName: r'publicKey')
  String? get publicKey;

  /// `device` only; base64url without padding
  @BuiltValueField(wireName: r'attestation')
  String? get attestation;

  @BuiltValueField(wireName: r'label')
  String? get label;

  @BuiltValueField(wireName: r'createdAt')
  String get createdAt;

  @BuiltValueField(wireName: r'lastUsedAt')
  String? get lastUsedAt;

  KeyWrap._();

  factory KeyWrap([void updates(KeyWrapBuilder b)]) = _$KeyWrap;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(KeyWrapBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<KeyWrap> get serializer => _$KeyWrapSerializer();
}

class _$KeyWrapSerializer implements PrimitiveSerializer<KeyWrap> {
  @override
  final Iterable<Type> types = const [KeyWrap, _$KeyWrap];

  @override
  final String wireName = r'KeyWrap';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    KeyWrap object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'kind';
    yield serializers.serialize(object.kind, specifiedType: const FullType(KeyWrapKindEnum));
    yield r'ref';
    yield object.ref == null
        ? null
        : serializers.serialize(object.ref, specifiedType: const FullType.nullable(String));
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
    yield r'wrapped';
    yield serializers.serialize(object.wrapped, specifiedType: const FullType(String));
    yield r'publicKey';
    yield object.publicKey == null
        ? null
        : serializers.serialize(object.publicKey, specifiedType: const FullType.nullable(String));
    yield r'attestation';
    yield object.attestation == null
        ? null
        : serializers.serialize(object.attestation, specifiedType: const FullType.nullable(String));
    yield r'label';
    yield object.label == null
        ? null
        : serializers.serialize(object.label, specifiedType: const FullType.nullable(String));
    yield r'createdAt';
    yield serializers.serialize(object.createdAt, specifiedType: const FullType(String));
    yield r'lastUsedAt';
    yield object.lastUsedAt == null
        ? null
        : serializers.serialize(object.lastUsedAt, specifiedType: const FullType.nullable(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    KeyWrap object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required KeyWrapBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.id = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(KeyWrapKindEnum),
          ) as KeyWrapKindEnum;
          result.kind = valueDes;
          break;
        case r'ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.ref = valueDes;
          break;
        case r'keyV':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.keyV = valueDes;
          break;
        case r'wrapped':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.wrapped = valueDes;
          break;
        case r'publicKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.publicKey = valueDes;
          break;
        case r'attestation':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.attestation = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.label = valueDes;
          break;
        case r'createdAt':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.createdAt = valueDes;
          break;
        case r'lastUsedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.lastUsedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  KeyWrap deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = KeyWrapBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class KeyWrapKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'passkey')
  static const KeyWrapKindEnum passkey = _$keyWrapKindEnum_passkey;
  @BuiltValueEnumConst(wireName: r'recovery')
  static const KeyWrapKindEnum recovery = _$keyWrapKindEnum_recovery;
  @BuiltValueEnumConst(wireName: r'device')
  static const KeyWrapKindEnum device = _$keyWrapKindEnum_device;
  @BuiltValueEnumConst(wireName: r'assistant')
  static const KeyWrapKindEnum assistant = _$keyWrapKindEnum_assistant;

  static Serializer<KeyWrapKindEnum> get serializer => _$keyWrapKindEnumSerializer;

  const KeyWrapKindEnum._(String name) : super(name);

  static BuiltSet<KeyWrapKindEnum> get values => _$keyWrapKindEnumValues;
  static KeyWrapKindEnum valueOf(String name) => _$keyWrapKindEnumValueOf(name);
}
