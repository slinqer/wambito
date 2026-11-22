//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_metrics_cohorts_inner.g.dart';

/// AdminMetricsCohortsInner
///
/// Properties:
/// * [weekStart]
/// * [size]
/// * [week1]
/// * [week4]
/// * [week12]
@BuiltValue()
abstract class AdminMetricsCohortsInner
    implements Built<AdminMetricsCohortsInner, AdminMetricsCohortsInnerBuilder> {
  @BuiltValueField(wireName: r'weekStart')
  String get weekStart;

  @BuiltValueField(wireName: r'size')
  int get size;

  @BuiltValueField(wireName: r'week1')
  int? get week1;

  @BuiltValueField(wireName: r'week4')
  int? get week4;

  @BuiltValueField(wireName: r'week12')
  int? get week12;

  AdminMetricsCohortsInner._();

  factory AdminMetricsCohortsInner([void updates(AdminMetricsCohortsInnerBuilder b)]) =
      _$AdminMetricsCohortsInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminMetricsCohortsInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminMetricsCohortsInner> get serializer =>
      _$AdminMetricsCohortsInnerSerializer();
}

class _$AdminMetricsCohortsInnerSerializer
    implements PrimitiveSerializer<AdminMetricsCohortsInner> {
  @override
  final Iterable<Type> types = const [AdminMetricsCohortsInner, _$AdminMetricsCohortsInner];

  @override
  final String wireName = r'AdminMetricsCohortsInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminMetricsCohortsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'weekStart';
    yield serializers.serialize(object.weekStart, specifiedType: const FullType(String));
    yield r'size';
    yield serializers.serialize(object.size, specifiedType: const FullType(int));
    yield r'week1';
    yield object.week1 == null
        ? null
        : serializers.serialize(object.week1, specifiedType: const FullType.nullable(int));
    yield r'week4';
    yield object.week4 == null
        ? null
        : serializers.serialize(object.week4, specifiedType: const FullType.nullable(int));
    yield r'week12';
    yield object.week12 == null
        ? null
        : serializers.serialize(object.week12, specifiedType: const FullType.nullable(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminMetricsCohortsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminMetricsCohortsInnerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'weekStart':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.weekStart = valueDes;
          break;
        case r'size':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.size = valueDes;
          break;
        case r'week1':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType.nullable(int)) as int?;
          if (valueDes == null) continue;
          result.week1 = valueDes;
          break;
        case r'week4':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType.nullable(int)) as int?;
          if (valueDes == null) continue;
          result.week4 = valueDes;
          break;
        case r'week12':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType.nullable(int)) as int?;
          if (valueDes == null) continue;
          result.week12 = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminMetricsCohortsInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminMetricsCohortsInnerBuilder();
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
