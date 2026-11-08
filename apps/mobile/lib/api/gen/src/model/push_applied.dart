//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_applied.g.dart';

/// PushApplied
///
/// Properties:
/// * [id]
/// * [version]
@BuiltValue()
abstract class PushApplied implements Built<PushApplied, PushAppliedBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'version')
  int get version;

  PushApplied._();

  factory PushApplied([void updates(PushAppliedBuilder b)]) = _$PushApplied;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushAppliedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushApplied> get serializer => _$PushAppliedSerializer();
}

class _$PushAppliedSerializer implements PrimitiveSerializer<PushApplied> {
  @override
  final Iterable<Type> types = const [PushApplied, _$PushApplied];

  @override
  final String wireName = r'PushApplied';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushApplied object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'version';
    yield serializers.serialize(object.version, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    PushApplied object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushAppliedBuilder result,
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
        case r'version':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.version = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PushApplied deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushAppliedBuilder();
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
