//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'start_signin.g.dart';

/// StartSignin
///
/// Properties:
/// * [commitment] - SHA-256(\"wambito/v1/pairing-commit\" || the browser's X25519 public key), 32 bytes, base64url
/// * [remember] - Keep me signed in on this browser: true gives a 60-day session renewed on use, false a 12-hour session whose cookie has no Max-Age
/// * [label] - What the phone shows, made from the user agent (\"Firefox on Mac\")
@BuiltValue()
abstract class StartSignin implements Built<StartSignin, StartSigninBuilder> {
  /// SHA-256(\"wambito/v1/pairing-commit\" || the browser's X25519 public key), 32 bytes, base64url
  @BuiltValueField(wireName: r'commitment')
  String get commitment;

  /// Keep me signed in on this browser: true gives a 60-day session renewed on use, false a 12-hour session whose cookie has no Max-Age
  @BuiltValueField(wireName: r'remember')
  bool get remember;

  /// What the phone shows, made from the user agent (\"Firefox on Mac\")
  @BuiltValueField(wireName: r'label')
  String get label;

  StartSignin._();

  factory StartSignin([void updates(StartSigninBuilder b)]) = _$StartSignin;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StartSigninBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StartSignin> get serializer => _$StartSigninSerializer();
}

class _$StartSigninSerializer implements PrimitiveSerializer<StartSignin> {
  @override
  final Iterable<Type> types = const [StartSignin, _$StartSignin];

  @override
  final String wireName = r'StartSignin';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StartSignin object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'commitment';
    yield serializers.serialize(object.commitment, specifiedType: const FullType(String));
    yield r'remember';
    yield serializers.serialize(object.remember, specifiedType: const FullType(bool));
    yield r'label';
    yield serializers.serialize(object.label, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    StartSignin object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StartSigninBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'commitment':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.commitment = valueDes;
          break;
        case r'remember':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(bool)) as bool;
          result.remember = valueDes;
          break;
        case r'label':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
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
  StartSignin deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StartSigninBuilder();
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
