//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'signin_started.g.dart';

/// SigninStarted
///
/// Properties:
/// * [id]
/// * [code] - 8 Crockford base32 characters, shown under the QR code
/// * [pollSecret] - 32 random bytes, base64url; only the browser holds it and sends it as `x-wambito-poll`
/// * [expiresAt]
@BuiltValue()
abstract class SigninStarted implements Built<SigninStarted, SigninStartedBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// 8 Crockford base32 characters, shown under the QR code
  @BuiltValueField(wireName: r'code')
  String get code;

  /// 32 random bytes, base64url; only the browser holds it and sends it as `x-wambito-poll`
  @BuiltValueField(wireName: r'pollSecret')
  String get pollSecret;

  @BuiltValueField(wireName: r'expiresAt')
  String get expiresAt;

  SigninStarted._();

  factory SigninStarted([void updates(SigninStartedBuilder b)]) = _$SigninStarted;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SigninStartedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SigninStarted> get serializer => _$SigninStartedSerializer();
}

class _$SigninStartedSerializer implements PrimitiveSerializer<SigninStarted> {
  @override
  final Iterable<Type> types = const [SigninStarted, _$SigninStarted];

  @override
  final String wireName = r'SigninStarted';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SigninStarted object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'code';
    yield serializers.serialize(object.code, specifiedType: const FullType(String));
    yield r'pollSecret';
    yield serializers.serialize(object.pollSecret, specifiedType: const FullType(String));
    yield r'expiresAt';
    yield serializers.serialize(object.expiresAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    SigninStarted object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SigninStartedBuilder result,
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
        case r'code':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.code = valueDes;
          break;
        case r'pollSecret':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.pollSecret = valueDes;
          break;
        case r'expiresAt':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SigninStarted deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SigninStartedBuilder();
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
