//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'key_link.g.dart';

/// KeyLink
///
/// Properties:
/// * [keyV] - The data key version this link leads to (>= 2)
/// * [link] - The previous data key sealed under this version's key, base64url without padding, 60 bytes decoded
@BuiltValue()
abstract class KeyLink implements Built<KeyLink, KeyLinkBuilder> {
  /// The data key version this link leads to (>= 2)
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  /// The previous data key sealed under this version's key, base64url without padding, 60 bytes decoded
  @BuiltValueField(wireName: r'link')
  String get link;

  KeyLink._();

  factory KeyLink([void updates(KeyLinkBuilder b)]) = _$KeyLink;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(KeyLinkBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<KeyLink> get serializer => _$KeyLinkSerializer();
}

class _$KeyLinkSerializer implements PrimitiveSerializer<KeyLink> {
  @override
  final Iterable<Type> types = const [KeyLink, _$KeyLink];

  @override
  final String wireName = r'KeyLink';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    KeyLink object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
    yield r'link';
    yield serializers.serialize(object.link, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    KeyLink object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required KeyLinkBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'keyV':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.keyV = valueDes;
          break;
        case r'link':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.link = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  KeyLink deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = KeyLinkBuilder();
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
