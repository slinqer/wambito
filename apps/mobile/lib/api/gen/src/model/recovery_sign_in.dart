//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'recovery_sign_in.g.dart';

/// RecoverySignIn
///
/// Properties:
/// * [lookup] - HKDF-SHA256 of the recovery secret under `wambito/v1/recovery/lookup`, 16 bytes, base64url
/// * [auth] - HKDF-SHA256 of the recovery secret under `wambito/v1/recovery/auth`, 32 bytes, base64url
@BuiltValue()
abstract class RecoverySignIn implements Built<RecoverySignIn, RecoverySignInBuilder> {
  /// HKDF-SHA256 of the recovery secret under `wambito/v1/recovery/lookup`, 16 bytes, base64url
  @BuiltValueField(wireName: r'lookup')
  String get lookup;

  /// HKDF-SHA256 of the recovery secret under `wambito/v1/recovery/auth`, 32 bytes, base64url
  @BuiltValueField(wireName: r'auth')
  String get auth;

  RecoverySignIn._();

  factory RecoverySignIn([void updates(RecoverySignInBuilder b)]) = _$RecoverySignIn;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RecoverySignInBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RecoverySignIn> get serializer => _$RecoverySignInSerializer();
}

class _$RecoverySignInSerializer implements PrimitiveSerializer<RecoverySignIn> {
  @override
  final Iterable<Type> types = const [RecoverySignIn, _$RecoverySignIn];

  @override
  final String wireName = r'RecoverySignIn';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RecoverySignIn object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'lookup';
    yield serializers.serialize(object.lookup, specifiedType: const FullType(String));
    yield r'auth';
    yield serializers.serialize(object.auth, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    RecoverySignIn object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RecoverySignInBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'lookup':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.lookup = valueDes;
          break;
        case r'auth':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.auth = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RecoverySignIn deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RecoverySignInBuilder();
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
