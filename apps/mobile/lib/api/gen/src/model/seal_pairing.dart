//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'seal_pairing.g.dart';

/// SealPairing
///
/// Properties:
/// * [sealed_] - The data key sealed to the new device's public key, base64url, 1–1024 bytes decoded; its first 32 bytes are the approver key
/// * [keyV] - The data key version the seal is bound to
@BuiltValue()
abstract class SealPairing implements Built<SealPairing, SealPairingBuilder> {
  /// The data key sealed to the new device's public key, base64url, 1–1024 bytes decoded; its first 32 bytes are the approver key
  @BuiltValueField(wireName: r'sealed')
  String get sealed_;

  /// The data key version the seal is bound to
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  SealPairing._();

  factory SealPairing([void updates(SealPairingBuilder b)]) = _$SealPairing;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SealPairingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SealPairing> get serializer => _$SealPairingSerializer();
}

class _$SealPairingSerializer implements PrimitiveSerializer<SealPairing> {
  @override
  final Iterable<Type> types = const [SealPairing, _$SealPairing];

  @override
  final String wireName = r'SealPairing';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SealPairing object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sealed';
    yield serializers.serialize(object.sealed_, specifiedType: const FullType(String));
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    SealPairing object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SealPairingBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sealed':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.sealed_ = valueDes;
          break;
        case r'keyV':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.keyV = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SealPairing deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SealPairingBuilder();
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
