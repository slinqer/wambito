//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_metrics_versions_inner.g.dart';

/// AdminMetricsVersionsInner
///
/// Properties:
/// * [platform]
/// * [appVersion]
/// * [users]
@BuiltValue()
abstract class AdminMetricsVersionsInner
    implements Built<AdminMetricsVersionsInner, AdminMetricsVersionsInnerBuilder> {
  @BuiltValueField(wireName: r'platform')
  String get platform;

  @BuiltValueField(wireName: r'appVersion')
  String get appVersion;

  @BuiltValueField(wireName: r'users')
  int get users;

  AdminMetricsVersionsInner._();

  factory AdminMetricsVersionsInner([void updates(AdminMetricsVersionsInnerBuilder b)]) =
      _$AdminMetricsVersionsInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminMetricsVersionsInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminMetricsVersionsInner> get serializer =>
      _$AdminMetricsVersionsInnerSerializer();
}

class _$AdminMetricsVersionsInnerSerializer
    implements PrimitiveSerializer<AdminMetricsVersionsInner> {
  @override
  final Iterable<Type> types = const [AdminMetricsVersionsInner, _$AdminMetricsVersionsInner];

  @override
  final String wireName = r'AdminMetricsVersionsInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminMetricsVersionsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'platform';
    yield serializers.serialize(object.platform, specifiedType: const FullType(String));
    yield r'appVersion';
    yield serializers.serialize(object.appVersion, specifiedType: const FullType(String));
    yield r'users';
    yield serializers.serialize(object.users, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminMetricsVersionsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminMetricsVersionsInnerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'platform':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.platform = valueDes;
          break;
        case r'appVersion':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.appVersion = valueDes;
          break;
        case r'users':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.users = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminMetricsVersionsInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminMetricsVersionsInnerBuilder();
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
