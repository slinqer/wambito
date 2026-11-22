//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/admin_metrics_daily_active_inner.dart';
import 'package:wambito/api/gen/src/model/admin_metrics_installs_by_platform_inner.dart';
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/admin_metrics_cohorts_inner.dart';
import 'package:wambito/api/gen/src/model/admin_metrics_versions_inner.dart';
import 'package:wambito/api/gen/src/model/admin_metrics_weekly_inner.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_metrics.g.dart';

/// AdminMetrics
///
/// Properties:
/// * [total]
/// * [withEmail]
/// * [guests]
/// * [active30d]
/// * [suspended]
/// * [signups7d]
/// * [signupsPrev7d]
/// * [weekly]
/// * [dailyActive]
/// * [cohorts]
/// * [installsByPlatform]
/// * [versions]
@BuiltValue()
abstract class AdminMetrics implements Built<AdminMetrics, AdminMetricsBuilder> {
  @BuiltValueField(wireName: r'total')
  int get total;

  @BuiltValueField(wireName: r'withEmail')
  int get withEmail;

  @BuiltValueField(wireName: r'guests')
  int get guests;

  @BuiltValueField(wireName: r'active30d')
  int get active30d;

  @BuiltValueField(wireName: r'suspended')
  int get suspended;

  @BuiltValueField(wireName: r'signups7d')
  int get signups7d;

  @BuiltValueField(wireName: r'signupsPrev7d')
  int get signupsPrev7d;

  @BuiltValueField(wireName: r'weekly')
  BuiltList<AdminMetricsWeeklyInner> get weekly;

  @BuiltValueField(wireName: r'dailyActive')
  BuiltList<AdminMetricsDailyActiveInner> get dailyActive;

  @BuiltValueField(wireName: r'cohorts')
  BuiltList<AdminMetricsCohortsInner> get cohorts;

  @BuiltValueField(wireName: r'installsByPlatform')
  BuiltList<AdminMetricsInstallsByPlatformInner> get installsByPlatform;

  @BuiltValueField(wireName: r'versions')
  BuiltList<AdminMetricsVersionsInner> get versions;

  AdminMetrics._();

  factory AdminMetrics([void updates(AdminMetricsBuilder b)]) = _$AdminMetrics;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminMetricsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminMetrics> get serializer => _$AdminMetricsSerializer();
}

class _$AdminMetricsSerializer implements PrimitiveSerializer<AdminMetrics> {
  @override
  final Iterable<Type> types = const [AdminMetrics, _$AdminMetrics];

  @override
  final String wireName = r'AdminMetrics';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminMetrics object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'total';
    yield serializers.serialize(object.total, specifiedType: const FullType(int));
    yield r'withEmail';
    yield serializers.serialize(object.withEmail, specifiedType: const FullType(int));
    yield r'guests';
    yield serializers.serialize(object.guests, specifiedType: const FullType(int));
    yield r'active30d';
    yield serializers.serialize(object.active30d, specifiedType: const FullType(int));
    yield r'suspended';
    yield serializers.serialize(object.suspended, specifiedType: const FullType(int));
    yield r'signups7d';
    yield serializers.serialize(object.signups7d, specifiedType: const FullType(int));
    yield r'signupsPrev7d';
    yield serializers.serialize(object.signupsPrev7d, specifiedType: const FullType(int));
    yield r'weekly';
    yield serializers.serialize(
      object.weekly,
      specifiedType: const FullType(BuiltList, [FullType(AdminMetricsWeeklyInner)]),
    );
    yield r'dailyActive';
    yield serializers.serialize(
      object.dailyActive,
      specifiedType: const FullType(BuiltList, [FullType(AdminMetricsDailyActiveInner)]),
    );
    yield r'cohorts';
    yield serializers.serialize(
      object.cohorts,
      specifiedType: const FullType(BuiltList, [FullType(AdminMetricsCohortsInner)]),
    );
    yield r'installsByPlatform';
    yield serializers.serialize(
      object.installsByPlatform,
      specifiedType: const FullType(BuiltList, [FullType(AdminMetricsInstallsByPlatformInner)]),
    );
    yield r'versions';
    yield serializers.serialize(
      object.versions,
      specifiedType: const FullType(BuiltList, [FullType(AdminMetricsVersionsInner)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminMetrics object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminMetricsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'total':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.total = valueDes;
          break;
        case r'withEmail':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.withEmail = valueDes;
          break;
        case r'guests':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.guests = valueDes;
          break;
        case r'active30d':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.active30d = valueDes;
          break;
        case r'suspended':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.suspended = valueDes;
          break;
        case r'signups7d':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.signups7d = valueDes;
          break;
        case r'signupsPrev7d':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.signupsPrev7d = valueDes;
          break;
        case r'weekly':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AdminMetricsWeeklyInner)]),
          ) as BuiltList<AdminMetricsWeeklyInner>;
          result.weekly.replace(valueDes);
          break;
        case r'dailyActive':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AdminMetricsDailyActiveInner)]),
          ) as BuiltList<AdminMetricsDailyActiveInner>;
          result.dailyActive.replace(valueDes);
          break;
        case r'cohorts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AdminMetricsCohortsInner)]),
          ) as BuiltList<AdminMetricsCohortsInner>;
          result.cohorts.replace(valueDes);
          break;
        case r'installsByPlatform':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [
              FullType(AdminMetricsInstallsByPlatformInner),
            ]),
          ) as BuiltList<AdminMetricsInstallsByPlatformInner>;
          result.installsByPlatform.replace(valueDes);
          break;
        case r'versions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AdminMetricsVersionsInner)]),
          ) as BuiltList<AdminMetricsVersionsInner>;
          result.versions.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminMetrics deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminMetricsBuilder();
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
