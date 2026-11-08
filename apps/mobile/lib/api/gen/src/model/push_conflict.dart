//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/sync_record.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_conflict.g.dart';

/// PushConflict
///
/// Properties:
/// * [id]
/// * [conflict]
@BuiltValue()
abstract class PushConflict implements Built<PushConflict, PushConflictBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'conflict')
  SyncRecord get conflict;

  PushConflict._();

  factory PushConflict([void updates(PushConflictBuilder b)]) = _$PushConflict;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushConflictBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushConflict> get serializer => _$PushConflictSerializer();
}

class _$PushConflictSerializer implements PrimitiveSerializer<PushConflict> {
  @override
  final Iterable<Type> types = const [PushConflict, _$PushConflict];

  @override
  final String wireName = r'PushConflict';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushConflict object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'conflict';
    yield serializers.serialize(object.conflict, specifiedType: const FullType(SyncRecord));
  }

  @override
  Object serialize(
    Serializers serializers,
    PushConflict object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushConflictBuilder result,
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
        case r'conflict':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SyncRecord),
          ) as SyncRecord;
          result.conflict.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PushConflict deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushConflictBuilder();
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
