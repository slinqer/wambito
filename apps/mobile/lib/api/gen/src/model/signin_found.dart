//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'signin_found.g.dart';

/// SigninFound
///
/// Properties:
/// * [id]
/// * [commitment] - base64url without padding
/// * [label]
/// * [expiresAt]
@BuiltValue(instantiable: false)
abstract class SigninFound {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// base64url without padding
  @BuiltValueField(wireName: r'commitment')
  String get commitment;

  @BuiltValueField(wireName: r'label')
  String get label;

  @BuiltValueField(wireName: r'expiresAt')
  String get expiresAt;

  @BuiltValueSerializer(custom: true)
  static Serializer<SigninFound> get serializer => _$SigninFoundSerializer();
}

class _$SigninFoundSerializer implements PrimitiveSerializer<SigninFound> {
  @override
  final Iterable<Type> types = const [SigninFound];

  @override
  final String wireName = r'SigninFound';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SigninFound object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'commitment';
    yield serializers.serialize(object.commitment, specifiedType: const FullType(String));
    yield r'label';
    yield serializers.serialize(object.label, specifiedType: const FullType(String));
    yield r'expiresAt';
    yield serializers.serialize(object.expiresAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    SigninFound object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  SigninFound deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($SigninFound))
        as $SigninFound;
  }
}

/// a concrete implementation of [SigninFound], since [SigninFound] is not instantiable
@BuiltValue(instantiable: true)
abstract class $SigninFound implements SigninFound, Built<$SigninFound, $SigninFoundBuilder> {
  $SigninFound._();

  factory $SigninFound([void Function($SigninFoundBuilder)? updates]) = _$$SigninFound;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($SigninFoundBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$SigninFound> get serializer => _$$SigninFoundSerializer();
}

class _$$SigninFoundSerializer implements PrimitiveSerializer<$SigninFound> {
  @override
  final Iterable<Type> types = const [$SigninFound, _$$SigninFound];

  @override
  final String wireName = r'$SigninFound';

  @override
  Object serialize(
    Serializers serializers,
    $SigninFound object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(SigninFound))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SigninFoundBuilder result,
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
        case r'commitment':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.commitment = valueDes;
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
  $SigninFound deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $SigninFoundBuilder();
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
