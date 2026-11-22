//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_metrics_installs_by_platform_inner.g.dart';

/// AdminMetricsInstallsByPlatformInner
///
/// Properties:
/// * [platform]
/// * [count]
@BuiltValue()
abstract class AdminMetricsInstallsByPlatformInner
    implements
        Built<AdminMetricsInstallsByPlatformInner, AdminMetricsInstallsByPlatformInnerBuilder> {
  @BuiltValueField(wireName: r'platform')
  AdminMetricsInstallsByPlatformInnerPlatformEnum get platform;
  // enum platformEnum {  android,  ios,  web,  unknown,  };

  @BuiltValueField(wireName: r'count')
  int get count;

  AdminMetricsInstallsByPlatformInner._();

  factory AdminMetricsInstallsByPlatformInner([
    void updates(AdminMetricsInstallsByPlatformInnerBuilder b),
  ]) = _$AdminMetricsInstallsByPlatformInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminMetricsInstallsByPlatformInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminMetricsInstallsByPlatformInner> get serializer =>
      _$AdminMetricsInstallsByPlatformInnerSerializer();
}

class _$AdminMetricsInstallsByPlatformInnerSerializer
    implements PrimitiveSerializer<AdminMetricsInstallsByPlatformInner> {
  @override
  final Iterable<Type> types = const [
    AdminMetricsInstallsByPlatformInner,
    _$AdminMetricsInstallsByPlatformInner,
  ];

  @override
  final String wireName = r'AdminMetricsInstallsByPlatformInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminMetricsInstallsByPlatformInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'platform';
    yield serializers.serialize(
      object.platform,
      specifiedType: const FullType(AdminMetricsInstallsByPlatformInnerPlatformEnum),
    );
    yield r'count';
    yield serializers.serialize(object.count, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminMetricsInstallsByPlatformInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminMetricsInstallsByPlatformInnerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'platform':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AdminMetricsInstallsByPlatformInnerPlatformEnum),
          ) as AdminMetricsInstallsByPlatformInnerPlatformEnum;
          result.platform = valueDes;
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
  AdminMetricsInstallsByPlatformInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminMetricsInstallsByPlatformInnerBuilder();
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

class AdminMetricsInstallsByPlatformInnerPlatformEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'android')
  static const AdminMetricsInstallsByPlatformInnerPlatformEnum android =
      _$adminMetricsInstallsByPlatformInnerPlatformEnum_android;
  @BuiltValueEnumConst(wireName: r'ios')
  static const AdminMetricsInstallsByPlatformInnerPlatformEnum ios =
      _$adminMetricsInstallsByPlatformInnerPlatformEnum_ios;
  @BuiltValueEnumConst(wireName: r'web')
  static const AdminMetricsInstallsByPlatformInnerPlatformEnum web =
      _$adminMetricsInstallsByPlatformInnerPlatformEnum_web;
  @BuiltValueEnumConst(wireName: r'unknown')
  static const AdminMetricsInstallsByPlatformInnerPlatformEnum unknown =
      _$adminMetricsInstallsByPlatformInnerPlatformEnum_unknown;

  static Serializer<AdminMetricsInstallsByPlatformInnerPlatformEnum> get serializer =>
      _$adminMetricsInstallsByPlatformInnerPlatformEnumSerializer;

  const AdminMetricsInstallsByPlatformInnerPlatformEnum._(String name) : super(name);

  static BuiltSet<AdminMetricsInstallsByPlatformInnerPlatformEnum> get values =>
      _$adminMetricsInstallsByPlatformInnerPlatformEnumValues;
  static AdminMetricsInstallsByPlatformInnerPlatformEnum valueOf(String name) =>
      _$adminMetricsInstallsByPlatformInnerPlatformEnumValueOf(name);
}
