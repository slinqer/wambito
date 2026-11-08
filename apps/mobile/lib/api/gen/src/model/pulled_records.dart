//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/sync_record.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pulled_records.g.dart';

/// PulledRecords
///
/// Properties:
/// * [records]
/// * [next] - The `since` of the next page; null when this page reaches `latest`
/// * [latest] - The newest version on the server; 0 when none
@BuiltValue()
abstract class PulledRecords implements Built<PulledRecords, PulledRecordsBuilder> {
  @BuiltValueField(wireName: r'records')
  BuiltList<SyncRecord> get records;

  /// The `since` of the next page; null when this page reaches `latest`
  @BuiltValueField(wireName: r'next')
  int? get next;

  /// The newest version on the server; 0 when none
  @BuiltValueField(wireName: r'latest')
  int get latest;

  PulledRecords._();

  factory PulledRecords([void updates(PulledRecordsBuilder b)]) = _$PulledRecords;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PulledRecordsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PulledRecords> get serializer => _$PulledRecordsSerializer();
}

class _$PulledRecordsSerializer implements PrimitiveSerializer<PulledRecords> {
  @override
  final Iterable<Type> types = const [PulledRecords, _$PulledRecords];

  @override
  final String wireName = r'PulledRecords';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PulledRecords object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'records';
    yield serializers.serialize(
      object.records,
      specifiedType: const FullType(BuiltList, [FullType(SyncRecord)]),
    );
    yield r'next';
    yield object.next == null
        ? null
        : serializers.serialize(object.next, specifiedType: const FullType.nullable(int));
    yield r'latest';
    yield serializers.serialize(object.latest, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    PulledRecords object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PulledRecordsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'records':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SyncRecord)]),
          ) as BuiltList<SyncRecord>;
          result.records.replace(valueDes);
          break;
        case r'next':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType.nullable(int)) as int?;
          if (valueDes == null) continue;
          result.next = valueDes;
          break;
        case r'latest':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.latest = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PulledRecords deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PulledRecordsBuilder();
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
