//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/key_wrap.dart';
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/key_link.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'assistant_wrap.g.dart';

/// AssistantWrap
///
/// Properties:
/// * [wrap]
/// * [links] - Ordered by `keyV`
@BuiltValue()
abstract class AssistantWrap implements Built<AssistantWrap, AssistantWrapBuilder> {
  @BuiltValueField(wireName: r'wrap')
  KeyWrap get wrap;

  /// Ordered by `keyV`
  @BuiltValueField(wireName: r'links')
  BuiltList<KeyLink> get links;

  AssistantWrap._();

  factory AssistantWrap([void updates(AssistantWrapBuilder b)]) = _$AssistantWrap;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AssistantWrapBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AssistantWrap> get serializer => _$AssistantWrapSerializer();
}

class _$AssistantWrapSerializer implements PrimitiveSerializer<AssistantWrap> {
  @override
  final Iterable<Type> types = const [AssistantWrap, _$AssistantWrap];

  @override
  final String wireName = r'AssistantWrap';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AssistantWrap object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'wrap';
    yield serializers.serialize(object.wrap, specifiedType: const FullType(KeyWrap));
    yield r'links';
    yield serializers.serialize(
      object.links,
      specifiedType: const FullType(BuiltList, [FullType(KeyLink)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AssistantWrap object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AssistantWrapBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'wrap':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(KeyWrap)) as KeyWrap;
          result.wrap.replace(valueDes);
          break;
        case r'links':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(KeyLink)]),
          ) as BuiltList<KeyLink>;
          result.links.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AssistantWrap deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AssistantWrapBuilder();
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
