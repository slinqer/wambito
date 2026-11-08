//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rotated_key_wrap.g.dart';

/// RotatedKeyWrap
///
/// Properties:
/// * [id]
/// * [kind]
/// * [ref] - The passkey's credential id (base64url), the device id, or the assistant's OAuth client id; none for `recovery`
/// * [keyV] - The data key version this wraps
/// * [wrapped] - The wrapped data key, base64url without padding, 1–1024 bytes decoded
/// * [publicKey] - `device` only, and required there: its X25519 public key, 32 bytes, base64url
/// * [label] - Shown in Settings (\"Pixel 9\", \"Firefox on Mac\")
@BuiltValue()
abstract class RotatedKeyWrap implements Built<RotatedKeyWrap, RotatedKeyWrapBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'kind')
  RotatedKeyWrapKindEnum get kind;
  // enum kindEnum {  passkey,  recovery,  device,  assistant,  };

  /// The passkey's credential id (base64url), the device id, or the assistant's OAuth client id; none for `recovery`
  @BuiltValueField(wireName: r'ref')
  String? get ref;

  /// The data key version this wraps
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  /// The wrapped data key, base64url without padding, 1–1024 bytes decoded
  @BuiltValueField(wireName: r'wrapped')
  String get wrapped;

  /// `device` only, and required there: its X25519 public key, 32 bytes, base64url
  @BuiltValueField(wireName: r'publicKey')
  String? get publicKey;

  /// Shown in Settings (\"Pixel 9\", \"Firefox on Mac\")
  @BuiltValueField(wireName: r'label')
  String? get label;

  RotatedKeyWrap._();

  factory RotatedKeyWrap([void updates(RotatedKeyWrapBuilder b)]) = _$RotatedKeyWrap;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RotatedKeyWrapBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RotatedKeyWrap> get serializer => _$RotatedKeyWrapSerializer();
}

class _$RotatedKeyWrapSerializer implements PrimitiveSerializer<RotatedKeyWrap> {
  @override
  final Iterable<Type> types = const [RotatedKeyWrap, _$RotatedKeyWrap];

  @override
  final String wireName = r'RotatedKeyWrap';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RotatedKeyWrap object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'kind';
    yield serializers.serialize(object.kind, specifiedType: const FullType(RotatedKeyWrapKindEnum));
    if (object.ref != null) {
      yield r'ref';
      yield serializers.serialize(object.ref, specifiedType: const FullType.nullable(String));
    }
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
    yield r'wrapped';
    yield serializers.serialize(object.wrapped, specifiedType: const FullType(String));
    if (object.publicKey != null) {
      yield r'publicKey';
      yield serializers.serialize(object.publicKey, specifiedType: const FullType.nullable(String));
    }
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(object.label, specifiedType: const FullType.nullable(String));
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RotatedKeyWrap object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RotatedKeyWrapBuilder result,
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
            specifiedType: const FullType(RotatedKeyWrapKindEnum),
          ) as RotatedKeyWrapKindEnum;
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
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.label = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RotatedKeyWrap deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RotatedKeyWrapBuilder();
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

class RotatedKeyWrapKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'passkey')
  static const RotatedKeyWrapKindEnum passkey = _$rotatedKeyWrapKindEnum_passkey;
  @BuiltValueEnumConst(wireName: r'recovery')
  static const RotatedKeyWrapKindEnum recovery = _$rotatedKeyWrapKindEnum_recovery;
  @BuiltValueEnumConst(wireName: r'device')
  static const RotatedKeyWrapKindEnum device = _$rotatedKeyWrapKindEnum_device;
  @BuiltValueEnumConst(wireName: r'assistant')
  static const RotatedKeyWrapKindEnum assistant = _$rotatedKeyWrapKindEnum_assistant;

  static Serializer<RotatedKeyWrapKindEnum> get serializer => _$rotatedKeyWrapKindEnumSerializer;

  const RotatedKeyWrapKindEnum._(String name) : super(name);

  static BuiltSet<RotatedKeyWrapKindEnum> get values => _$rotatedKeyWrapKindEnumValues;
  static RotatedKeyWrapKindEnum valueOf(String name) => _$rotatedKeyWrapKindEnumValueOf(name);
}
