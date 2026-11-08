//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/key_wrap.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'key_wraps.g.dart';

/// KeyWraps
///
/// Properties:
/// * [wraps]
@BuiltValue()
abstract class KeyWraps implements Built<KeyWraps, KeyWrapsBuilder> {
  @BuiltValueField(wireName: r'wraps')
  BuiltList<KeyWrap> get wraps;

  KeyWraps._();

  factory KeyWraps([void updates(KeyWrapsBuilder b)]) = _$KeyWraps;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(KeyWrapsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<KeyWraps> get serializer => _$KeyWrapsSerializer();
}

class _$KeyWrapsSerializer implements PrimitiveSerializer<KeyWraps> {
  @override
  final Iterable<Type> types = const [KeyWraps, _$KeyWraps];

  @override
  final String wireName = r'KeyWraps';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    KeyWraps object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'wraps';
    yield serializers.serialize(
      object.wraps,
      specifiedType: const FullType(BuiltList, [FullType(KeyWrap)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    KeyWraps object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required KeyWrapsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'wraps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(KeyWrap)]),
          ) as BuiltList<KeyWrap>;
          result.wraps.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  KeyWraps deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = KeyWrapsBuilder();
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
