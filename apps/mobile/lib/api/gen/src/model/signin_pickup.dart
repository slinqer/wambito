//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'signin_pickup.g.dart';

/// SigninPickup
///
/// Properties:
/// * [sealed_] - base64url
/// * [keyV] - The data key version the seal is bound to
/// * [userId] - The account signed in to
@BuiltValue()
abstract class SigninPickup implements Built<SigninPickup, SigninPickupBuilder> {
  /// base64url
  @BuiltValueField(wireName: r'sealed')
  String get sealed_;

  /// The data key version the seal is bound to
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  /// The account signed in to
  @BuiltValueField(wireName: r'userId')
  String get userId;

  SigninPickup._();

  factory SigninPickup([void updates(SigninPickupBuilder b)]) = _$SigninPickup;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SigninPickupBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SigninPickup> get serializer => _$SigninPickupSerializer();
}

class _$SigninPickupSerializer implements PrimitiveSerializer<SigninPickup> {
  @override
  final Iterable<Type> types = const [SigninPickup, _$SigninPickup];

  @override
  final String wireName = r'SigninPickup';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SigninPickup object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sealed';
    yield serializers.serialize(object.sealed_, specifiedType: const FullType(String));
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
    yield r'userId';
    yield serializers.serialize(object.userId, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    SigninPickup object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SigninPickupBuilder result,
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
        case r'userId':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.userId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SigninPickup deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SigninPickupBuilder();
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
