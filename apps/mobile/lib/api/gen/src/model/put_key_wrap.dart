//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'put_key_wrap.g.dart';

/// PutKeyWrap
///
/// Properties:
/// * [kind]
/// * [ref] - The passkey's credential id (base64url), the device id, or the assistant's OAuth client id; none for `recovery`
/// * [keyV] - The data key version this wraps
/// * [wrapped] - The wrapped data key, base64url without padding, 1–1024 bytes decoded
/// * [publicKey] - `device` only, and required there (422 `attestation_required`): its X25519 public key, 32 bytes, base64url
/// * [attestation] - `device` only, and required there (422 `attestation_required`): HMAC-SHA256, 32 bytes, base64url, under a key derived from the data key over user id, wrap id and public key. The server stores it and cannot check it; devices verify it before sealing the data key to this key.
/// * [label] - Shown in Settings (\"Pixel 9\", \"Firefox on Mac\")
@BuiltValue()
abstract class PutKeyWrap implements Built<PutKeyWrap, PutKeyWrapBuilder> {
  @BuiltValueField(wireName: r'kind')
  PutKeyWrapKindEnum get kind;
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

  /// `device` only, and required there (422 `attestation_required`): its X25519 public key, 32 bytes, base64url
  @BuiltValueField(wireName: r'publicKey')
  String? get publicKey;

  /// `device` only, and required there (422 `attestation_required`): HMAC-SHA256, 32 bytes, base64url, under a key derived from the data key over user id, wrap id and public key. The server stores it and cannot check it; devices verify it before sealing the data key to this key.
  @BuiltValueField(wireName: r'attestation')
  String? get attestation;

  /// Shown in Settings (\"Pixel 9\", \"Firefox on Mac\")
  @BuiltValueField(wireName: r'label')
  String? get label;

  PutKeyWrap._();

  factory PutKeyWrap([void updates(PutKeyWrapBuilder b)]) = _$PutKeyWrap;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PutKeyWrapBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PutKeyWrap> get serializer => _$PutKeyWrapSerializer();
}

class _$PutKeyWrapSerializer implements PrimitiveSerializer<PutKeyWrap> {
  @override
  final Iterable<Type> types = const [PutKeyWrap, _$PutKeyWrap];

  @override
  final String wireName = r'PutKeyWrap';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PutKeyWrap object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(object.kind, specifiedType: const FullType(PutKeyWrapKindEnum));
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
    if (object.attestation != null) {
      yield r'attestation';
      yield serializers.serialize(
        object.attestation,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(object.label, specifiedType: const FullType.nullable(String));
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PutKeyWrap object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PutKeyWrapBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PutKeyWrapKindEnum),
          ) as PutKeyWrapKindEnum;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PutKeyWrap deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PutKeyWrapBuilder();
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

class PutKeyWrapKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'passkey')
  static const PutKeyWrapKindEnum passkey = _$putKeyWrapKindEnum_passkey;
  @BuiltValueEnumConst(wireName: r'recovery')
  static const PutKeyWrapKindEnum recovery = _$putKeyWrapKindEnum_recovery;
  @BuiltValueEnumConst(wireName: r'device')
  static const PutKeyWrapKindEnum device = _$putKeyWrapKindEnum_device;
  @BuiltValueEnumConst(wireName: r'assistant')
  static const PutKeyWrapKindEnum assistant = _$putKeyWrapKindEnum_assistant;

  static Serializer<PutKeyWrapKindEnum> get serializer => _$putKeyWrapKindEnumSerializer;

  const PutKeyWrapKindEnum._(String name) : super(name);

  static BuiltSet<PutKeyWrapKindEnum> get values => _$putKeyWrapKindEnumValues;
  static PutKeyWrapKindEnum valueOf(String name) => _$putKeyWrapKindEnumValueOf(name);
}
