//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/sync_change.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_records.g.dart';

/// PushRecords
///
/// Properties:
/// * [changes]
@BuiltValue()
abstract class PushRecords implements Built<PushRecords, PushRecordsBuilder> {
  @BuiltValueField(wireName: r'changes')
  BuiltList<SyncChange> get changes;

  PushRecords._();

  factory PushRecords([void updates(PushRecordsBuilder b)]) = _$PushRecords;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushRecordsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushRecords> get serializer => _$PushRecordsSerializer();
}

class _$PushRecordsSerializer implements PrimitiveSerializer<PushRecords> {
  @override
  final Iterable<Type> types = const [PushRecords, _$PushRecords];

  @override
  final String wireName = r'PushRecords';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushRecords object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'changes';
    yield serializers.serialize(
      object.changes,
      specifiedType: const FullType(BuiltList, [FullType(SyncChange)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PushRecords object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushRecordsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'changes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SyncChange)]),
          ) as BuiltList<SyncChange>;
          result.changes.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PushRecords deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushRecordsBuilder();
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
