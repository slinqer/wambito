//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/push_result.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_results.g.dart';

/// PushResults
///
/// Properties:
/// * [results]
@BuiltValue()
abstract class PushResults implements Built<PushResults, PushResultsBuilder> {
  @BuiltValueField(wireName: r'results')
  BuiltList<PushResult> get results;

  PushResults._();

  factory PushResults([void updates(PushResultsBuilder b)]) = _$PushResults;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushResultsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushResults> get serializer => _$PushResultsSerializer();
}

class _$PushResultsSerializer implements PrimitiveSerializer<PushResults> {
  @override
  final Iterable<Type> types = const [PushResults, _$PushResults];

  @override
  final String wireName = r'PushResults';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushResults object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'results';
    yield serializers.serialize(
      object.results,
      specifiedType: const FullType(BuiltList, [FullType(PushResult)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PushResults object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushResultsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'results':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PushResult)]),
          ) as BuiltList<PushResult>;
          result.results.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PushResults deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushResultsBuilder();
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
