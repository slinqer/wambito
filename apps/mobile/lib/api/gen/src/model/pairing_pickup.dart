//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pairing_pickup.g.dart';

/// PairingPickup
///
/// Properties:
/// * [sealed_] - base64url; null until the other device seals
@BuiltValue()
abstract class PairingPickup implements Built<PairingPickup, PairingPickupBuilder> {
  /// base64url; null until the other device seals
  @BuiltValueField(wireName: r'sealed')
  String? get sealed_;

  PairingPickup._();

  factory PairingPickup([void updates(PairingPickupBuilder b)]) = _$PairingPickup;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PairingPickupBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PairingPickup> get serializer => _$PairingPickupSerializer();
}

class _$PairingPickupSerializer implements PrimitiveSerializer<PairingPickup> {
  @override
  final Iterable<Type> types = const [PairingPickup, _$PairingPickup];

  @override
  final String wireName = r'PairingPickup';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PairingPickup object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sealed';
    yield object.sealed_ == null
        ? null
        : serializers.serialize(object.sealed_, specifiedType: const FullType.nullable(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    PairingPickup object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PairingPickupBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sealed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sealed_ = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PairingPickup deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PairingPickupBuilder();
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
