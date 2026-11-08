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
/// * [sealed_] - base64url
/// * [keyV] - The data key version the seal is bound to
@BuiltValue()
abstract class PairingPickup implements Built<PairingPickup, PairingPickupBuilder> {
  /// base64url
  @BuiltValueField(wireName: r'sealed')
  String get sealed_;

  /// The data key version the seal is bound to
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

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
    yield serializers.serialize(object.sealed_, specifiedType: const FullType(String));
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
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
