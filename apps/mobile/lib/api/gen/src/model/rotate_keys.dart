//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/rotated_key_wrap.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rotate_keys.g.dart';

/// RotateKeys
///
/// Properties:
/// * [keyV] - The new key version: current + 1
/// * [wraps]
@BuiltValue()
abstract class RotateKeys implements Built<RotateKeys, RotateKeysBuilder> {
  /// The new key version: current + 1
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  @BuiltValueField(wireName: r'wraps')
  BuiltList<RotatedKeyWrap> get wraps;

  RotateKeys._();

  factory RotateKeys([void updates(RotateKeysBuilder b)]) = _$RotateKeys;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RotateKeysBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RotateKeys> get serializer => _$RotateKeysSerializer();
}

class _$RotateKeysSerializer implements PrimitiveSerializer<RotateKeys> {
  @override
  final Iterable<Type> types = const [RotateKeys, _$RotateKeys];

  @override
  final String wireName = r'RotateKeys';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RotateKeys object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
    yield r'wraps';
    yield serializers.serialize(
      object.wraps,
      specifiedType: const FullType(BuiltList, [FullType(RotatedKeyWrap)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RotateKeys object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RotateKeysBuilder result,
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
        case r'wraps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RotatedKeyWrap)]),
          ) as BuiltList<RotatedKeyWrap>;
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
  RotateKeys deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RotateKeysBuilder();
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
