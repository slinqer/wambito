//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_metrics_daily_active_inner.g.dart';

/// AdminMetricsDailyActiveInner
///
/// Properties:
/// * [day]
/// * [count]
@BuiltValue()
abstract class AdminMetricsDailyActiveInner
    implements Built<AdminMetricsDailyActiveInner, AdminMetricsDailyActiveInnerBuilder> {
  @BuiltValueField(wireName: r'day')
  String get day;

  @BuiltValueField(wireName: r'count')
  int get count;

  AdminMetricsDailyActiveInner._();

  factory AdminMetricsDailyActiveInner([void updates(AdminMetricsDailyActiveInnerBuilder b)]) =
      _$AdminMetricsDailyActiveInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminMetricsDailyActiveInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminMetricsDailyActiveInner> get serializer =>
      _$AdminMetricsDailyActiveInnerSerializer();
}

class _$AdminMetricsDailyActiveInnerSerializer
    implements PrimitiveSerializer<AdminMetricsDailyActiveInner> {
  @override
  final Iterable<Type> types = const [AdminMetricsDailyActiveInner, _$AdminMetricsDailyActiveInner];

  @override
  final String wireName = r'AdminMetricsDailyActiveInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminMetricsDailyActiveInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'day';
    yield serializers.serialize(object.day, specifiedType: const FullType(String));
    yield r'count';
    yield serializers.serialize(object.count, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminMetricsDailyActiveInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminMetricsDailyActiveInnerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'day':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.day = valueDes;
          break;
        case r'count':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.count = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminMetricsDailyActiveInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminMetricsDailyActiveInnerBuilder();
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
