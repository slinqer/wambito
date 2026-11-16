//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/signin_found.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'signin_view.g.dart';

/// SigninView
///
/// Properties:
/// * [id]
/// * [commitment] - base64url without padding
/// * [label]
/// * [expiresAt]
/// * [publicKey] - base64url; null until set
@BuiltValue()
abstract class SigninView implements SigninFound, Built<SigninView, SigninViewBuilder> {
  /// base64url; null until set
  @BuiltValueField(wireName: r'publicKey')
  String? get publicKey;

  SigninView._();

  factory SigninView([void updates(SigninViewBuilder b)]) = _$SigninView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SigninViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SigninView> get serializer => _$SigninViewSerializer();
}

class _$SigninViewSerializer implements PrimitiveSerializer<SigninView> {
  @override
  final Iterable<Type> types = const [SigninView, _$SigninView];

  @override
  final String wireName = r'SigninView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SigninView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'commitment';
    yield serializers.serialize(object.commitment, specifiedType: const FullType(String));
    yield r'publicKey';
    yield object.publicKey == null
        ? null
        : serializers.serialize(object.publicKey, specifiedType: const FullType.nullable(String));
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'label';
    yield serializers.serialize(object.label, specifiedType: const FullType(String));
    yield r'expiresAt';
    yield serializers.serialize(object.expiresAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    SigninView object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SigninViewBuilder result,
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
        case r'publicKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.publicKey = valueDes;
          break;
        case r'id':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.id = valueDes;
          break;
        case r'label':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.label = valueDes;
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
  SigninView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SigninViewBuilder();
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
